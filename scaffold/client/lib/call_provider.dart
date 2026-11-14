// OLIVE BRANCH — the call provider seam. UNVERIFIED on real devices (the
// parts that need a media engine run only on hardware; the interface, the
// grant parsing and the calm wording below are covered by flutter test).
//
// MASTERFILE §16.2 #6, REVERSED a third time (2026-11-09): calls run on the
// owner's self-hosted Jitsi by default and LiveKit stays selectable. WHICH
// engine carries a call is decided by the server's grant (`provider`), never
// by a build flag, so one build can place and answer calls on either.
//
// This file is deliberately engine-free: it imports neither livekit_client nor
// jitsi_meet_flutter_sdk. call_screen.dart and call_knock_screen.dart depend
// only on what is declared here (tests/call_ui_imports_test.dart enforces it
// at source level). The two engines live behind it:
//   livekit_call_provider.dart  — Room/track primitives, our own call UI
//   jitsi_call_provider.dart    — the Jitsi SDK's native call screen
// and call_provider_registry.dart is the only place that names both.
//
// What a provider does NOT decide: who may call whom, knock/answer, day-part
// and posture gates, session rules. All of that is the server's, provider-
// agnostic, and arrives as an already-authorised grant.
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'call_modes.dart' show CallMode;
import 'degradation_banner.dart' show Condition, Quality;

enum CallProviderKind { jitsi, livekit }

/// The provider-specific half of a call response (server/call_grant.mjs),
/// parsed. `provider` absent means an older/dev server that only speaks
/// LiveKit (`token` + `wsURL`), which is how tools/local-call-room-server.mjs
/// still answers.
class CallGrant {
  const CallGrant._({
    required this.kind,
    required this.displayName,
    this.identity,
    this.token,
    this.wsURL,
    this.jwt,
    this.room,
    this.serverURL,
    this.moderator = false,
    this.observerOnly = false,
  });

  /// LiveKit: a signed room token and the project URL it was signed for.
  const CallGrant.livekit({required String token, required String wsURL, String displayName = '', String? identity})
      : this._(kind: CallProviderKind.livekit, displayName: displayName, identity: identity, token: token, wsURL: wsURL);

  /// Jitsi: a short-lived per-participant JWT scoped to one (derived) room on
  /// one https server. Adults moderate, the child does not; an observer-only
  /// guardian joins muted with a hang-up-only toolbar (advisory on Jitsi).
  const CallGrant.jitsi({
    required String jwt,
    required String room,
    required String serverURL,
    String displayName = '',
    String? identity,
    bool moderator = false,
    bool observerOnly = false,
  }) : this._(kind: CallProviderKind.jitsi, displayName: displayName, identity: identity, jwt: jwt,
            room: room, serverURL: serverURL, moderator: moderator, observerOnly: observerOnly);

  final CallProviderKind kind;
  final String displayName;
  final String? identity;
  final String? token;
  final String? wsURL;
  final String? jwt;
  final String? room;
  final String? serverURL;
  final bool moderator;
  final bool observerOnly;

  /// Throws [FormatException] for a body that is not a usable grant, so a
  /// half-formed response can never reach an engine as a half-formed join.
  factory CallGrant.fromJson(Map<String, dynamic> j) {
    final provider = j['provider'] as String?;
    final name = (j['displayName'] as String?) ?? '';
    final identity = j['identity'] as String?;
    String need(String k) {
      final v = j[k];
      if (v is String && v.isNotEmpty) return v;
      throw FormatException('call grant is missing "$k"');
    }
    if (provider == 'jitsi') {
      return CallGrant.jitsi(
        jwt: need('jwt'), room: need('room'), serverURL: need('serverURL'),
        displayName: name, identity: identity,
        moderator: j['moderator'] == true, observerOnly: j['observerOnly'] == true,
      );
    }
    if (provider == null || provider == 'livekit') {
      return CallGrant.livekit(token: need('token'), wsURL: need('wsURL'), displayName: name, identity: identity);
    }
    throw FormatException('unknown call provider "$provider"');
  }
}

/// Why a join could not start. Reasons, not messages: the screen turns these
/// into audience-aware wording ([callUnavailableLine]); raw exception text
/// never reaches a child.
enum CallUnavailableReason {
  /// The server said the provider is not switched on (503 call_provider_unavailable).
  providerOff,
  /// Nothing reachable: no network, a timeout, the host not answering.
  unreachable,
  /// The grant itself was unusable, or the transport policy refused it
  /// (for example a non-https Jitsi address in a release build).
  refused,
}

class CallUnavailableException implements Exception {
  const CallUnavailableException(this.reason, [this.detail]);
  final CallUnavailableReason reason;
  /// For logs and a guardian-only hint. Never shown to a child, never a secret.
  final String? detail;
  @override
  String toString() => 'CallUnavailableException($reason${detail == null ? '' : ': $detail'})';
}

enum CallPhase { connecting, connected, reconnecting, ended }

/// An immutable snapshot of what the call screen needs to draw.
class CallViewState {
  const CallViewState({
    this.phase = CallPhase.connecting,
    this.remoteName,
    this.remoteMode = CallMode.video,
    this.micEnabled = true,
    this.cameraEnabled = true,
    this.condition = Condition.good,
    this.awaitingResumeConsent = false,
    this.hasRemoteVideo = false,
    this.hasLocalVideo = false,
    this.everConnected = false,
  });

  final CallPhase phase;
  final String? remoteName;
  /// What the OTHER side chose, as far as this device knows. Assumed video
  /// until told otherwise (never blame an unreported state).
  final CallMode remoteMode;
  final bool micEnabled;
  final bool cameraEnabled;
  /// Fed to degradation_banner.dart's hysteresis; an engine with no quality
  /// report (Jitsi) simply stays [Condition.good].
  final Condition condition;
  /// §5.23.2 "resuming asks first": set after an unexpected reconnect that
  /// found the camera on; the camera stays off until her own tap.
  final bool awaitingResumeConsent;
  /// Whether a picture currently exists to draw (else the calm listening
  /// surface is shown, never a black rectangle).
  final bool hasRemoteVideo;
  final bool hasLocalVideo;
  /// True once the call has really connected at least once. An end BEFORE this
  /// is "the call never started" (calm unavailable screen, no end-of-call
  /// record); an end after it is a normal hang-up.
  final bool everConnected;

  CallViewState copyWith({
    CallPhase? phase,
    String? remoteName,
    bool clearRemoteName = false,
    CallMode? remoteMode,
    bool? micEnabled,
    bool? cameraEnabled,
    Condition? condition,
    bool? awaitingResumeConsent,
    bool? hasRemoteVideo,
    bool? hasLocalVideo,
  }) => CallViewState(
        phase: phase ?? this.phase,
        remoteName: clearRemoteName ? null : (remoteName ?? this.remoteName),
        remoteMode: remoteMode ?? this.remoteMode,
        micEnabled: micEnabled ?? this.micEnabled,
        cameraEnabled: cameraEnabled ?? this.cameraEnabled,
        condition: condition ?? this.condition,
        awaitingResumeConsent: awaitingResumeConsent ?? this.awaitingResumeConsent,
        hasRemoteVideo: hasRemoteVideo ?? this.hasRemoteVideo,
        hasLocalVideo: hasLocalVideo ?? this.hasLocalVideo,
        everConnected: everConnected || (phase ?? this.phase) == CallPhase.connected,
      );
}

class CallJoinOptions {
  const CallJoinOptions({required this.displayName, this.mode = CallMode.video, required this.isGuardian});
  final String displayName;
  /// §5.23.1: audio-only is a choice, not a punishment.
  final CallMode mode;
  final bool isGuardian;
}

/// What the call screen is allowed to know about a call engine.
abstract class CallProvider {
  CallProviderKind get kind;

  /// True when the engine draws the call itself, on its own native screen
  /// (Jitsi). Our screen then shows a calm resting surface behind it and does
  /// not build the in-call controls or video views.
  bool get rendersOwnScreen;

  CallViewState get state;
  Stream<CallViewState> get states;

  /// Throws [CallUnavailableException] when the call cannot start.
  Future<void> join(CallGrant grant, CallJoinOptions options);

  /// Ask the engine to hang up. [CallPhase.ended] arrives through [states].
  Future<void> leave();

  Future<void> setMicrophoneEnabled(bool enabled);

  /// Switches HER OWN camera only (never anyone else's).
  Future<void> setCameraEnabled(bool enabled);

  /// A hint from the degradation ladder; engines with no such knob ignore it.
  void applyQuality(Quality quality);

  /// Video surfaces for our own call UI; null when there is none to show.
  Widget? buildRemoteVideo();
  Widget? buildLocalVideo();

  Future<void> dispose();
}

/// Builds the engine a grant calls for. Injected into the screens so tests
/// use a fake and the real registry stays the only code naming both engines.
typedef CallProviderFactory = CallProvider Function(CallGrant grant);

/// Jitsi must be reached over https in a release build (the transport policy
/// the whole app holds); debug builds may also use http for a local test
/// server. Pure, so it is unit-tested; the LAN self-signed certificate is
/// handled natively and narrowly (network_security_config.xml pins one cert
/// for one LAN address), never by weakening this check.
bool jitsiServerUrlAllowed(String url, {required bool release}) {
  final u = Uri.tryParse(url);
  if (u == null || !u.hasAuthority || u.host.isEmpty) return false;
  if (u.userInfo.isNotEmpty) return false;
  if (u.scheme == 'https') return true;
  return !release && u.scheme == 'http';
}

/// Words a child must never be shown on the call surfaces (P1-P11: nothing
/// alarming, nothing that blames her, her family or the connection).
const List<String> callBannedWords = [
  'error', 'failed', 'failure', 'wrong', 'sorry', 'problem', 'invalid', 'denied',
  'unauthorized', 'exception', 'refused', 'timeout', 'timed out', 'offline',
  'disconnected', 'lost', 'broken', 'crash', 'unable', 'forbidden',
];

/// The line shown when a call cannot start. Soft for a child, plain for an
/// adult; never a raw exception, never a stack, never an address or a key.
String callUnavailableLine(CallUnavailableReason reason, {required bool isGuardian}) {
  if (!isGuardian) {
    return switch (reason) {
      CallUnavailableReason.providerOff => "Calls aren't switched on just now. Let's try again in a little while.",
      CallUnavailableReason.unreachable => "The call isn't ready just now. Let's try again in a little while.",
      CallUnavailableReason.refused => "The call isn't ready just now. Let's try again in a little while.",
    };
  }
  return switch (reason) {
    CallUnavailableReason.providerOff =>
      "Calls are switched off. On the home PC run calls-on, then try again.",
    CallUnavailableReason.unreachable =>
      "Can't reach the call right now. Check you are on the home Wi-Fi and that the home PC is on with calls switched on.",
    CallUnavailableReason.refused =>
      "This call can't be started from here. Check the call settings on the server, then try again.",
  };
}

/// "Calling Dad…" (guardian view of the child's name too): same everywhere.
String callingLine(String who) => 'Calling $who…';
String joiningLine(String who) => 'Joining $who…';
const String reconnectingLine = 'Still here. Getting the picture back…';

/// A tiny in-memory engine for tests of anything that depends only on the
/// interface (call_screen_test.dart, call_provider_test.dart). It records
/// calls and lets a test drive [CallViewState] changes.
class FakeCallProvider implements CallProvider {
  FakeCallProvider({
    this.kind = CallProviderKind.livekit,
    this.rendersOwnScreen = false,
    this.joinError,
    this.connectOnJoin = true,
  });

  @override
  final CallProviderKind kind;
  @override
  final bool rendersOwnScreen;
  /// When set, [join] throws it (the "provider unavailable" path).
  final CallUnavailableException? joinError;
  /// When false, [join] returns while still connecting (a test then drives [emit]).
  final bool connectOnJoin;

  final List<String> calls = [];
  CallGrant? joinedWith;
  CallJoinOptions? joinedOptions;
  Quality? lastQuality;
  bool disposed = false;

  CallViewState _state = const CallViewState();
  final StreamController<CallViewState> _ctl = StreamController<CallViewState>.broadcast();

  @override
  CallViewState get state => _state;
  @override
  Stream<CallViewState> get states => _ctl.stream;

  /// Test hook: move the call to a new state.
  void emit(CallViewState s) {
    _state = s;
    if (!_ctl.isClosed) _ctl.add(s);
  }

  @override
  Future<void> join(CallGrant grant, CallJoinOptions options) async {
    calls.add('join');
    joinedWith = grant;
    joinedOptions = options;
    if (joinError != null) throw joinError!;
    emit(_state.copyWith(
      phase: connectOnJoin ? CallPhase.connected : CallPhase.connecting,
      cameraEnabled: options.mode == CallMode.video));
  }

  @override
  Future<void> leave() async {
    calls.add('leave');
    emit(_state.copyWith(phase: CallPhase.ended));
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    calls.add('mic:$enabled');
    emit(_state.copyWith(micEnabled: enabled));
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    calls.add('camera:$enabled');
    emit(_state.copyWith(cameraEnabled: enabled));
  }

  @override
  void applyQuality(Quality quality) {
    lastQuality = quality;
  }

  @override
  Widget? buildRemoteVideo() => null;
  @override
  Widget? buildLocalVideo() => null;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _ctl.close();
  }
}
