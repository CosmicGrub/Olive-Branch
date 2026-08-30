// OLIVE BRANCH — real-time call, LiveKit Cloud. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline — manually built and
// run via `flutter analyze` / `flutter test` this session; real two-device
// verification is next, pending a real LiveKit Cloud project). §5.19/§5.23
// the call. §16.2 #6 REVERSED AGAIN — this build was self-hosted Jitsi Meet
// + Jitsi Videobridge; LiveKit Cloud replaces it. See
// docs/superpowers/specs/2026-08-29-livekit-call-migration-design.md for
// the full account of why (real, lived self-host operational cost this
// session; the structural distance/quality ceiling of one self-hosted JVB
// instance vs LiveKit's real global edge network) and what it does and does
// not cover.
//
// The one thing the two devices still need to agree on is which room to
// join, and that coordination reuses real, tested logic —
// packages/session-runtime/src/rooms.mjs's newRoomName()/mintToken(), which
// still enforce I1 (room name never guessable) and I4 (authorization gate)
// — served locally by scaffold/tools/local-call-room-server.mjs, or for
// real by server/routes.mjs's POST /v1/children/:childId/calls and
// /calls/:sessionId/join routes. mintLiveKitToken()
// (packages/session-runtime/src/livekit-token.mjs) turns that same real
// grant into the signed JWT LiveKit actually requires to let anyone join at
// all — pure serialization, not a new authorization decision (see that
// file's own header).
//
// A REAL, STRUCTURAL DIFFERENCE FROM THE JITSI BUILD THIS REPLACES, worth
// naming plainly: Jitsi's SDK handed this screen a complete, prebuilt
// native call UI (mute/camera/hangup, participant tiles, its own settings/
// chat/lobby screens) that this file spent real effort stripping down for
// §8.1 (no settings affordance anywhere for the child) and the child-only
// chat-disable audit named in this file's own prior header. LiveKit is
// room/track primitives, not a UI — so THIS file now builds its own real,
// minimal call screen below. That is a genuine trade: more code here, but
// none of it is spent fighting someone else's meeting-app chrome, and
// nothing resembling Jitsi's own settings/chat/lobby screens exists to
// disable in the first place, because none of it was ever built. §8.1 is
// satisfied by construction, not a flag.
//
// A SECOND real, structural difference: LiveKit is an SFU — media is
// ALWAYS relayed through it, for every participant count, with no P2P mode
// to disable. Jitsi defaulted P2P to ON for exactly-two-participant calls
// (config.js's own config.p2p.enabled: true) and needed real, layered
// defense-in-depth (ENABLE_P2P=0 server-side, this file's own
// iceTransportPolicy: 'relay' override) to guarantee §5.21.1 ("all media is
// relayed, always" — neither device may ever learn the other's real IP, a
// protective-order-relevant safety requirement). LiveKit's architecture
// never offers that path at all — §5.21.1 holds structurally here, not by
// a flag that has to be remembered and kept in sync across two layers.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'degradation_banner.dart';

/// LOCAL DEV/TEST ONLY — tools/local-call-room-server.mjs. Not a production
/// endpoint.
///
/// Loopback rather than a LAN IP, on purpose: a hardcoded LAN address goes
/// stale the moment the dev machine's network changes, and silently breaks
/// two-device testing with no clue why. `127.0.0.1` on the *device* reaches
/// the dev machine's `local-call-room-server.mjs` over
/// `adb reverse tcp:8787 tcp:8787`, run once per physical device before
/// installing — see that script's own header. This works over USB
/// regardless of whether the phones and the dev machine share a WiFi
/// network at all — and, unlike the self-hosted-Jitsi build this replaces,
/// nothing else here needs that trick: the actual call media reaches
/// LiveKit Cloud over the device's own normal internet connection, real
/// WiFi or cellular, no LAN/adb-reverse/self-signed-cert dance required.
const devRoomServerBase = 'http://127.0.0.1:8787';

/// 'ivy' is the only child identity any real call site uses (child_home
/// .dart, call_knock_screen.dart's own answer path); every other value —
/// today only 'dad' — is a guardian. A real, tested distinction, not a
/// guess: guardian_more.dart's own real call-start route already refuses a
/// child principal outright (child_cannot_start_call), so 'who' and "which
/// side of the ladder can this device leave kiosk lock" already agree in
/// every real call path this client has. A top-level function, not a
/// private method on [_CallScreenState], so a widget test can exercise it
/// directly without needing to pump a whole [CallScreen] and force it
/// through its own real (and, in a test sandbox, unavoidably platform-
/// channel-hanging) join attempt.
bool isGuardianWho(String who) => who != 'ivy';

/// Maps the hysteresis ladder's three video tiers (degradation_banner.dart's
/// own `Quality` enum, already real, tested, and unchanged by this
/// migration) onto LiveKit's own per-track subscription quality — the real
/// mechanism (`RemoteTrackPublication.setVideoQuality`) that actually asks
/// the SFU to serve a different simulcast layer, not a cosmetic label.
lk.VideoQuality videoQualityFor(Quality q) => switch (q) {
  Quality.q720 => lk.VideoQuality.HIGH,
  Quality.q360 => lk.VideoQuality.MEDIUM,
  Quality.q180 => lk.VideoQuality.LOW,
};

/// ConnectionQuality.poor/lost are the only two states this hysteresis
/// treats as "strained" — .unknown (no report yet) and .good/.excellent are
/// both "the connection is fine," matching this app's own "never blame a
/// connection that's merely unreported" posture (degradation_banner.dart's
/// own streamBanned list already refuses to name a network as the problem;
/// treating .unknown as strained would do exactly that on every call's
/// first ~second, before LiveKit has reported anything real yet).
Condition conditionFor(lk.ConnectionQuality q) =>
    (q == lk.ConnectionQuality.poor || q == lk.ConnectionQuality.lost)
        ? Condition.strained
        : Condition.good;

class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.who,
    required this.displayName,
    this.knownToken,
    this.knownWsURL,
    this.onCallEnd,
  });

  /// 'dad' or 'ivy' — matches local-call-room-server.mjs's fixed identities.
  final String who;
  final String displayName;
  /// When supplied, [_fetchToken] is skipped entirely and the call connects
  /// with THIS exact, already-minted token instead — either the real
  /// `POST /v1/children/:childId/calls` route's response (the caller
  /// starting a fresh call) or the real `POST
  /// /v1/children/:childId/calls/:sessionId/join` route's response (the
  /// callee answering a knock for an EXISTING call — see call_knock_screen
  /// .dart's own doc comment on why answering needs a real second server
  /// round-trip under LiveKit, unlike the bare-room-name join the Jitsi
  /// build this replaces got away with). Both null (the default) is
  /// byte-for-byte the dev-room-server fetch path every existing call site
  /// not answering a real knock already uses (child_home.dart,
  /// guardian_home.dart, main_live_child_call_test.dart). Always supplied
  /// together when either is — there is no real call site left that has one
  /// without the other, unlike the old Jitsi build's `knownServerURL`
  /// (optional even with `knownRoom` set, because a push payload carried no
  /// deployment config); a real LiveKit join always needs both a token AND
  /// the project URL it was signed for.
  final String? knownToken;
  final String? knownWsURL;

  /// Fires once, right before this screen navigates away on a real,
  /// SDK-reported room disconnect — never on the error path (nothing was
  /// ever really joined there to end). Deliberately a caller-supplied
  /// callback rather than this screen knowing a baseUrl/session/childId/
  /// sessionId itself: mirrors guardian_more.dart's own onCallStarted seam,
  /// keeping CallScreen decoupled from OliveApi entirely, same as it
  /// already was under Jitsi. A real call site supplies one that calls the
  /// real POST /v1/children/:childId/calls/:sessionId/end route
  /// (guardian_more.dart's own `_startRealCall`); null here is a safe,
  /// honest no-op for every call site that doesn't have a real sessionId to
  /// close (e.g. the dev room server's fixed session has none).
  final Future<void> Function()? onCallEnd;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

enum _CallStatus { fetchingToken, joining, inCall, error }

class _CallScreenState extends State<CallScreen> {
  // Deliberately NOT constructed eagerly (e.g. `= lk.Room()` at declaration)
  // — livekit_client's own Room constructor starts a real, periodic
  // internal cache-cleanup timer (Engine's PendingTrackQueue -> TTLMap,
  // confirmed by reading that class's own source: no dispose()/cancel()
  // exists on it at all, so Room.dispose() cannot stop it once started).
  // Constructing this only right before an actual connect() attempt means
  // a call that never gets past _fetchToken() (no real dev room server or
  // network reachable — the exact case every existing widget test in
  // call_screen_test.dart already exercises) never starts that timer at
  // all, rather than leaking one flutter_test's own pending-timer check
  // would otherwise catch on every single test in this file.
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  _CallStatus _status = _CallStatus.fetchingToken;
  String? _errorMessage;

  lk.VideoTrack? _localVideoTrack;
  lk.VideoTrack? _remoteVideoTrack;
  lk.RemoteTrackPublication? _remoteVideoPublication;
  String? _remoteName;

  // Real live call quality (folded into this migration, MASTERFILE §5.28/
  // §8.14) — degradation_banner.dart's own hysteresis state machine,
  // completely unchanged, fed a real ConnectionQuality report instead of
  // the "(demo)" screen's clock-driven fake wobble. See conditionFor()'s
  // own doc comment for why .unknown is never treated as strained.
  StreamState _stream = newStream();
  StreamNotice? _notice;
  lk.ConnectionQuality _lastKnownQuality = lk.ConnectionQuality.unknown;
  Timer? _qualityTicker;
  static const _qualityTickMs = 250; // matches degradation_banner.dart's own _tickMs exactly

  // livekit_client exposes setMicrophoneEnabled()/setCameraEnabled() but no
  // matching isXEnabled() getter (confirmed by reading LocalParticipant's
  // own source, not assumed) — tracked here instead, toggled only by this
  // screen's own two calls to those setters, so it can never drift from
  // what was actually last requested.
  bool _micEnabled = true;
  bool _cameraEnabled = true;

  @override
  void initState() {
    super.initState();
    _startCall();
  }

  /// 'ivy' is the only child identity any real call site uses — see
  /// isGuardianWho's own doc comment for the fuller account.
  bool get _isGuardian => isGuardianWho(widget.who);

  Future<Map<String, dynamic>> _fetchToken() async {
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
      _status = _CallStatus.fetchingToken;
      _errorMessage = null;
    });
    try {
      final String token;
      final String wsURL;
      if (widget.knownToken != null) {
        token = widget.knownToken!;
        wsURL = widget.knownWsURL!;
      } else {
        final data = await _fetchToken();
        token = data['token'] as String;
        wsURL = data['wsURL'] as String;
      }

      if (!mounted) return;
      setState(() => _status = _CallStatus.joining);

      // §16.2 #6 / §5.20 — the OLD Jitsi build had to hand kiosk lock-task
      // pinning off to a second native Activity here (its own SDK opened
      // calls in a separate singleTask Activity, which lock-task pinning
      // refuses to launch as a second task). A LiveKit call is this same
      // screen, in this same Activity — no second Activity is ever
      // launched, so that handoff has no problem left to solve. Not called
      // here. kiosk_channel.dart's own beginCallHandoff() is left in place,
      // unremoved, pending real kiosk-lock verification on the Fold5 with a
      // real LiveKit project (see this migration's own spec's testing
      // plan) — this comment is the disclosed reasoning for why that
      // verification is expected to confirm removal, not a guess presented
      // as settled.

      // Only constructed here, not eagerly — see the field's own doc
      // comment for why (a real, un-cancellable internal SDK timer).
      final room = lk.Room();
      _room = room;
      _listener = room.createListener()..listen(_handleRoomEvent);
      _qualityTicker = Timer.periodic(
        const Duration(milliseconds: _qualityTickMs), (_) => _tickQuality());

      await room.connect(wsURL, token);
      await room.localParticipant?.setCameraEnabled(true);
      await room.localParticipant?.setMicrophoneEnabled(true);

      if (mounted) setState(() => _status = _CallStatus.inCall);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = _CallStatus.error;
        _errorMessage = '$error';
      });
    }
  }

  void _handleRoomEvent(lk.RoomEvent event) {
    if (event is lk.RoomDisconnectedEvent) {
      // Fire-and-forget, deliberately: popping the Navigator must never
      // wait on a network call, and a failed end-call POST must never
      // strand the user on a screen that already knows the call is over.
      // See widget.onCallEnd's own doc comment for what this is and is not
      // (record-keeping only — no server-side media revocation happens
      // here, a real, disclosed, separate gap).
      widget.onCallEnd?.call();
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    if (event is lk.ParticipantConnectedEvent) {
      final p = event.participant;
      if (mounted) setState(() => _remoteName = p.name.isNotEmpty ? p.name : p.identity);
      return;
    }
    if (event is lk.ParticipantDisconnectedEvent) {
      if (mounted) {
        setState(() {
          _remoteName = null;
          _remoteVideoTrack = null;
          _remoteVideoPublication = null;
        });
      }
      return;
    }
    if (event is lk.LocalTrackPublishedEvent) {
      final t = event.publication.track;
      if (t is lk.LocalVideoTrack && mounted) setState(() => _localVideoTrack = t);
      return;
    }
    if (event is lk.TrackSubscribedEvent) {
      final track = event.track;
      if (track is lk.VideoTrack && mounted) {
        setState(() {
          _remoteVideoTrack = track;
          _remoteVideoPublication = event.publication;
        });
      }
      return;
    }
    if (event is lk.TrackUnsubscribedEvent) {
      if (event.track is lk.VideoTrack && mounted) {
        setState(() {
          _remoteVideoTrack = null;
          _remoteVideoPublication = null;
        });
      }
      return;
    }
    if (event is lk.ParticipantConnectionQualityUpdatedEvent) {
      // Only the remote participant's own reported quality drives the
      // ladder — our own local publish quality isn't what this exists to
      // protect against, and LiveKit reports both under the same event
      // type.
      if (event.participant is! lk.LocalParticipant) {
        _lastKnownQuality = event.connectionQuality;
      }
      return;
    }
  }

  /// Runs every _qualityTickMs off a real Timer, exactly the way the
  /// "(demo)" screen's own _tick() always did — the only thing that
  /// changed is _lastKnownQuality now comes from a real
  /// ParticipantConnectionQualityUpdatedEvent instead of a manual "wobble
  /// the line" test control. evaluate()/noticeFor()/markTold() are called
  /// completely unmodified from degradation_banner.dart.
  void _tickQuality() {
    final result = evaluate(_stream, StreamTick(conditionFor(_lastKnownQuality), _qualityTickMs));
    if (result.changed != StreamChange.none) {
      _remoteVideoPublication?.setVideoQuality(videoQualityFor(result.state.quality));
    }
    final notice = noticeFor(result.state);
    if (!mounted) return;
    setState(() {
      _stream = notice != null ? markTold(result.state) : result.state;
      if (notice != null) _notice = notice;
    });
  }

  @override
  void dispose() {
    _qualityTicker?.cancel();
    _listener?.dispose();
    _room?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: switch (_status) {
      _CallStatus.fetchingToken => const Center(child: _Status(message: 'Finding the call…')),
      _CallStatus.joining => const Center(child: _Status(message: 'Joining…')),
      _CallStatus.inCall => _InCallView(
          localTrack: _localVideoTrack,
          remoteTrack: _remoteVideoTrack,
          remoteName: _remoteName,
          notice: _notice,
          isGuardian: _isGuardian,
          onHangUp: () async {
            // Non-null by construction: this branch only renders once
            // _startCall() has already reached _CallStatus.inCall, which
            // only happens after _room was assigned.
            await _room?.disconnect();
          },
          onToggleMic: () async {
            await _room?.localParticipant?.setMicrophoneEnabled(!_micEnabled);
            if (mounted) setState(() => _micEnabled = !_micEnabled);
          },
          onToggleCamera: () async {
            await _room?.localParticipant?.setCameraEnabled(!_cameraEnabled);
            if (mounted) setState(() => _cameraEnabled = !_cameraEnabled);
          },
          micEnabled: _micEnabled,
          cameraEnabled: _cameraEnabled,
        ),
      _CallStatus.error => Center(
          child: _ErrorState(
            message: _errorMessage ?? 'Could not start the call.',
            onRetry: _startCall,
          ),
        ),
    },
  );
}

class _Status extends StatelessWidget {
  const _Status({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    const CircularProgressIndicator(color: Colors.white),
    const SizedBox(height: 16),
    Text(message, style: const TextStyle(color: Colors.white)),
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
      Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
      const SizedBox(height: 16),
      FilledButton(onPressed: onRetry, child: const Text('Try again')),
      TextButton(
        onPressed: () => Navigator.of(context).maybePop(),
        child: const Text('Back', style: TextStyle(color: Colors.white70)),
      ),
    ]),
  );
}

/// The real, minimal call UI this migration requires (see this file's own
/// header for why building this is the right trade, not a regression).
/// Deliberately plain: a full-bleed remote tile with a small local self-view
/// in the corner, the exact real DegradationBanner this app already has and
/// tested, and three controls — mic, camera, hang up. No chat, no settings,
/// no lobby toggle, no invite-people UI exists here at all — §8.1 held by
/// construction, not a flag remembered per role the way the Jitsi build
/// needed (`callFeatureFlagsFor`'s own now-removed role-conditional chat
/// flag).
class _InCallView extends StatelessWidget {
  const _InCallView({
    required this.localTrack,
    required this.remoteTrack,
    required this.remoteName,
    required this.notice,
    required this.isGuardian,
    required this.onHangUp,
    required this.onToggleMic,
    required this.onToggleCamera,
    required this.micEnabled,
    required this.cameraEnabled,
  });

  final lk.VideoTrack? localTrack;
  final lk.VideoTrack? remoteTrack;
  final String? remoteName;
  final StreamNotice? notice;
  final bool isGuardian;
  final Future<void> Function() onHangUp;
  final Future<void> Function() onToggleMic;
  final Future<void> Function() onToggleCamera;
  final bool micEnabled;
  final bool cameraEnabled;

  @override
  Widget build(BuildContext context) => Stack(children: [
    Positioned.fill(
      child: remoteTrack != null
          ? lk.VideoTrackRenderer(remoteTrack!)
          : Container(
              color: const Color(0xFF1A1A1A),
              alignment: Alignment.center,
              child: Text(
                remoteName == null ? 'Waiting for the other side…' : '$remoteName is connecting…',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
    ),
    DegradationBanner(notice: notice),
    if (localTrack != null)
      Positioned(
        top: 16, right: 16, width: 110, height: 150,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: lk.VideoTrackRenderer(localTrack!, mirrorMode: lk.VideoViewMirrorMode.mirror),
        ),
      ),
    Positioned(
      left: 0, right: 0, bottom: 32,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _CallControlButton(
          icon: micEnabled ? Icons.mic : Icons.mic_off,
          onPressed: onToggleMic,
        ),
        const SizedBox(width: 24),
        _CallControlButton(
          icon: Icons.call_end,
          backgroundColor: Colors.redAccent,
          onPressed: onHangUp,
        ),
        const SizedBox(width: 24),
        _CallControlButton(
          icon: cameraEnabled ? Icons.videocam : Icons.videocam_off,
          onPressed: onToggleCamera,
        ),
      ]),
    ),
  ]);
}

class _CallControlButton extends StatelessWidget {
  const _CallControlButton({required this.icon, required this.onPressed, this.backgroundColor});
  final IconData icon;
  final Future<void> Function() onPressed;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) => Material(
    color: backgroundColor ?? Colors.white24,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    ),
  );
}
