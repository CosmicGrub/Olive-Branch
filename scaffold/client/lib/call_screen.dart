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
import 'call_modes.dart';
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

/// §5.21.1 — "all media is relayed, always." LiveKit's SFU architecture
/// never offers a peer-to-peer path to negotiate in the first place (see
/// this file's own header), so this is real defense-in-depth rather than
/// the load-bearing control it was under Jitsi — the same posture
/// `security.ts`'s own (dead, pre-LiveKit) `CallPolicy` already documented
/// as the right trade: "both parties are exposed to us rather than to each
/// other." Forcing relay-only ICE means this client's own IP is visible
/// exclusively to LiveKit's edge, never negotiated as a host/srflx
/// candidate toward anything else. Spiked against the installed SDK
/// (livekit_client 2.11.0) before writing this, not guessed: `RTCIceTransportPolicy
/// .relay` is a real field the SDK's own internal TURN-connectivity check
/// already exercises (`connection_check/checks/turn.dart`), not a
/// speculative API.
const _connectOptions = lk.ConnectOptions(
  rtcConfiguration: lk.RTCConfiguration(iceTransportPolicy: lk.RTCIceTransportPolicy.relay),
);

/// Network-resilience roadmap A1 — `adaptiveStream`/`dynacast` both default
/// to `false` in this SDK version; a repo-wide search before this change
/// found this client never constructed a `RoomOptions` at all, so neither
/// was ever on despite MASTERFILE's own accessibility table promising
/// "audio-only fallback, SVC/simulcast... rural grandparent, school wifi."
/// `adaptiveStream` asks the SFU to serve a lower simulcast layer to a
/// subscriber whose own tile is small/off-screen; `dynacast` stops
/// publishing a layer nobody is currently subscribed to. Neither changes
/// what §5.28's own hysteresis ladder does — that's still
/// `RemoteTrackPublication.setVideoQuality()`, unchanged — this is a
/// separate, complementary SDK-level saving that applies before the
/// ladder's own logic ever has to step in.
final _roomOptions = const lk.RoomOptions(adaptiveStream: true, dynacast: true);

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
    this.initialMode = CallMode.video,
  });

  /// 'dad' or 'ivy' — matches local-call-room-server.mjs's fixed identities.
  final String who;
  final String displayName;

  /// MASTERFILE §5.23.1 — audio-only as a CHOICE, not a punishment. Set by
  /// whichever real answer she tapped (call_knock_screen.dart's "Answer" vs
  /// "Just talking" — see [CallKnockScreen.answerOptions]) or by the
  /// equivalent choice on the originating side. Defaults to video: every
  /// existing call site that doesn't yet offer the choice (a bare "Call
  /// $childName" tile with no mode picker) keeps behaving exactly as before
  /// this field existed.
  final CallMode initialMode;
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

enum _CallStatus { fetchingToken, joining, inCall, reconnecting, error }

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
  // MASTERFILE §5.23.1 — starts from her real choice (Answer vs Just
  // talking), not always-on. Audio is never affected by mode — §8.14's
  // NEVER_SHED / call_audio holds regardless of which button she tapped.
  late bool _cameraEnabled = widget.initialMode == CallMode.video;

  /// What the OTHER participant's own mode is, as far as this device knows
  /// — read from their real LiveKit participant metadata (never inferred
  /// from their video track alone, which can also be absent for reasons
  /// that aren't a chosen mode at all: still connecting, a real network
  /// drop). Assumed video until told otherwise — matches this file's own
  /// "never blame an unreported state" posture elsewhere (conditionFor's own
  /// doc comment).
  CallMode _remoteMode = CallMode.video;

  /// MASTERFILE §5.23.2 — "resuming asks first." Set when an UNEXPECTED
  /// disconnect interrupts a call that had a real camera on; a successful
  /// reconnect then holds the camera off and waits for her own tap here,
  /// rather than a dropped-and-recovered connection silently starting to
  /// transmit her room again the moment the wifi came back.
  bool _awaitingResumeConsent = false;

  // Reconnect-on-unexpected-disconnect state — see _attemptReconnect's own
  // doc comment for the real, root-caused bug this exists to recover from
  // (a confirmed livekit_client SDK race, not a network/product issue).
  // _lastToken/_lastWsURL are the same grant already proven to work for
  // THIS call — a LiveKit token is a reusable room-access grant, not a
  // one-shot value, and TOKEN_TTL_SECONDS (10 min server-side) comfortably
  // outlives the few-second gap a reconnect attempt needs.
  String? _lastToken;
  String? _lastWsURL;
  // Set right before the user's own hang-up disconnects the room, so
  // RoomDisconnectedEvent can tell "she hung up" apart from "the SDK
  // dropped us" — only the latter should trigger a reconnect.
  bool _hangingUp = false;
  int _reconnectAttempts = 0;
  static const _maxReconnectAttempts = 2;
  // Reentrancy guard — see _handleRoomEvent's own RoomDisconnectedEvent
  // branch for why a single bad connection can fire this event more than
  // once and must not spawn more than one concurrent reconnect attempt.
  bool _reconnecting = false;

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

  /// Publishes THIS device's own real mode to the other side — the real
  /// transport for [modeForOther]'s line ("Voice only just now.") to
  /// actually reach him, since MASTERFILE §5.23.1 requires he be told the
  /// call is voice-only, not left to guess from an absent video track
  /// (which also happens for reasons that aren't a chosen mode at all —
  /// still connecting, a real network drop).
  ///
  /// A real-time DATA MESSAGE ([LocalParticipant.publishData]), deliberately
  /// NOT participant metadata ([LocalParticipant.setMetadata]) — every real
  /// grant this client's own tokens carry sets `canUpdateOwnMetadata: false`
  /// (packages/session-runtime/src/rooms.ts, tested by session.test.mjs's
  /// own I2 assertion: "no self-renaming in a child's room"), so a
  /// metadata-based version of this would be silently rejected server-side
  /// on every real call this app ever makes — confirmed directly against a
  /// real token minted by local-call-room-server.mjs this session, not
  /// assumed from the SDK docs alone. `canPublishData` IS granted (true for
  /// a publishing participant), and a transient UI signal like this one is
  /// exactly what that permission is for — it carries no identity claim,
  /// unlike metadata. Mode only, never the cause — [causeNeverDisclosed]
  /// holds by construction here: the payload has no field for one to leak
  /// through in the first place. Best-effort: a failed publish must never
  /// block or fail the call itself.
  Future<void> _publishMode() async {
    final mode = _cameraEnabled ? CallMode.video : CallMode.audioOnly;
    try {
      await _room?.localParticipant?.publishData(
        utf8.encode(jsonEncode({'mode': mode == CallMode.audioOnly ? 'audio_only' : 'video'})),
        reliable: true,
        topic: 'olive.call_mode');
    } catch (e) {
      debugPrint('[olive.call] publishData(mode) failed (non-fatal, mode stays local-only): $e');
    }
  }

  /// Real switch, mid-call, for HERSELF only — canSwitchOwnCamera() is true,
  /// canSwitchOthersCamera() is false, and this method has no way to reach
  /// anyone else's [_room] to violate that even by mistake.
  Future<void> _setMode(CallMode mode) async {
    final wantsCamera = mode == CallMode.video;
    if (wantsCamera == _cameraEnabled) return;
    await _room?.localParticipant?.setCameraEnabled(wantsCamera);
    if (mounted) setState(() => _cameraEnabled = wantsCamera);
    unawaited(_publishMode());
  }

  Future<void> _startCall() async {
    setState(() {
      _status = _CallStatus.fetchingToken;
      _errorMessage = null;
    });
    // Fresh call attempt (first try, or "Try again" after a real error) —
    // neither a stale hang-up flag nor a stale retry budget from a
    // previous attempt should carry over into this one.
    _hangingUp = false;
    _reconnectAttempts = 0;
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
      _lastToken = token;
      _lastWsURL = wsURL;

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
      final room = lk.Room(roomOptions: _roomOptions);
      _room = room;
      _listener = room.createListener()..listen(_handleRoomEvent);
      _qualityTicker = Timer.periodic(
        const Duration(milliseconds: _qualityTickMs), (_) => _tickQuality());

      await room.connect(wsURL, token, connectOptions: _connectOptions);
      // Respects her real choice — §5.23.1, not always-on. Mic is still
      // unconditional: audio is §8.14's NEVER_SHED, never gated by mode.
      await room.localParticipant?.setCameraEnabled(_cameraEnabled);
      await room.localParticipant?.setMicrophoneEnabled(true);
      unawaited(_publishMode());

      if (mounted) setState(() => _status = _CallStatus.inCall);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = _CallStatus.error;
        _errorMessage = _honestErrorMessage(error);
      });
    }
  }

  /// Network-resilience roadmap, Track B Option 1 — "the call is simply
  /// unavailable offline" needs an HONEST unavailable state, not a raw
  /// exception surfacing on screen. Before this, a genuine no-connectivity
  /// failure ('$error' on a [SocketException]/[TimeoutException]) would show
  /// text like "Failed host lookup" or "OS Error: No address associated with
  /// hostname" verbatim — exactly the kind of technical, alarming phrasing
  /// degradation_banner.dart's own [streamBanned] list already exists to
  /// keep off a child's screen mid-call, just never applied to the
  /// call-never-started case this screen also renders. This is a case a
  /// child can genuinely reach: [CallScreen] is not guardian-only.
  ///
  /// [SocketException]/[TimeoutException] specifically mean "nothing
  /// reachable at all" — the real, no-internet-path scenario, distinct from
  /// a real authorization/config error (still shown, since a guardian
  /// debugging a real setup problem needs the actual detail, and that class
  /// of error is unreachable from anywhere a child-only flow would land).
  static String _honestErrorMessage(Object error) {
    if (error is SocketException || error is TimeoutException) {
      return "Can't reach the call right now.";
    }
    return '$error';
  }

  void _handleRoomEvent(lk.RoomEvent event) {
    if (event is lk.RoomDisconnectedEvent) {
      // Network-resilience roadmap A4 — this manual reconnect layer is only
      // sound if RoomDisconnectedEvent genuinely fires after the SDK's own
      // native resilience has already given up, not before or instead of
      // it. Nothing in this repo confirmed that ordering against real
      // production traffic before this line existed — it was assumed from
      // docs. Logged, not asserted: the real answer is "collect enough of
      // these across enough real calls to know," not something one comment
      // can settle. `_lastKnownQuality` is included because the roadmap's
      // own finding was that per-participant ConnectionQuality reports
      // `lost` strictly earlier than any room-level event this handler can
      // see — this line is what would let a later reader confirm or refute
      // that ordering from real logs instead of re-guessing it.
      debugPrint('[olive.call] RoomDisconnectedEvent received — '
          'reconnecting=$_reconnecting hangingUp=$_hangingUp '
          'attempts=$_reconnectAttempts lastKnownQuality=$_lastKnownQuality '
          'reason=${event.reason}');
      if (_reconnecting) {
        // Already mid-reconnect — a room in a genuinely broken state can
        // fire RoomDisconnectedEvent more than once (confirmed live: a
        // burst of DISCONNECTED/FAILED events from the same underlying
        // failure). Reacting to each one would spawn overlapping
        // _attemptReconnect() calls, each racing to construct its own
        // replacement Room — exactly the kind of concurrent-state bug that
        // produces a crash loop instead of a clean recovery. One in flight
        // is enough; this event is redundant with it.
        return;
      }
      if (_hangingUp || _reconnectAttempts >= _maxReconnectAttempts) {
        // Either she genuinely hung up, or reconnecting has already been
        // tried and exhausted its budget — same real end-of-call path as
        // before this reconnect logic existed. Fire-and-forget,
        // deliberately: popping the Navigator must never wait on a
        // network call, and a failed end-call POST must never strand the
        // user on a screen that already knows the call is over. See
        // widget.onCallEnd's own doc comment for what this is and is not
        // (record-keeping only — no server-side media revocation happens
        // here, a real, disclosed, separate gap).
        widget.onCallEnd?.call();
        if (mounted) unawaited(Navigator.of(context).maybePop());
        return;
      }
      // An UNEXPECTED disconnect (not the user's own hang-up) — try to
      // recover instead of stranding her on a dead/black screen. Real,
      // root-caused reason this fires even after a genuinely successful
      // connection: a confirmed livekit_client SDK race (Room._on
      // ParticipantUpdateEvent's own events.waitFor<RoomConnectedEvent>()
      // one-shot listener can miss an already-fired connect and throw a
      // TimeoutException ~10s later, which tears the room down out from
      // under a call that had already exchanged real media) — see this
      // session's own direct SDK-source investigation. Not caught here as
      // a thrown exception (it's raised deep inside the SDK's own internal
      // event handling, not on this file's own call stack) — this event
      // is the one reliable, observable signal that it happened.
      unawaited(_attemptReconnect());
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
    if (event is lk.LocalTrackUnpublishedEvent) {
      // Real correctness fix: turning her own camera off (§5.23.1's
      // mid-call switch) used to leave _localVideoTrack pointing at a
      // disabled track — the self-view thumbnail would keep rendering a
      // frozen last frame instead of honestly disappearing. Only video
      // matters here; an unpublished audio track says nothing about mode.
      if (event.publication.kind == lk.TrackType.VIDEO && mounted) {
        setState(() => _localVideoTrack = null);
      }
      return;
    }
    if (event is lk.DataReceivedEvent) {
      // The real transport _publishMode() writes to — see that method's own
      // doc comment for why this is a data message and not participant
      // metadata. Only ever sent by the remote side about themselves (this
      // device's own mode is already the source of truth in
      // _cameraEnabled) — topic-scoped so a future second data channel on
      // this same room can't be misread as a mode update.
      if (event.topic != 'olive.call_mode') return;
      try {
        final decoded = jsonDecode(utf8.decode(event.data)) as Map<String, dynamic>;
        final mode = decoded['mode'] as String?;
        if (mounted) {
          setState(() => _remoteMode = mode == 'audio_only' ? CallMode.audioOnly : CallMode.video);
        }
      } catch (e) {
        // A malformed/foreign payload must never crash the call over a
        // cosmetic label — fall back to assuming video (this file's own
        // "never blame an unreported state" posture).
        debugPrint('[olive.call] could not parse remote mode data (non-fatal): $e');
      }
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
        // A1/A4 — network-resilience roadmap: this is the earlier signal
        // the roadmap's own research found (ConnectionQuality.lost fires
        // before room-level Reconnecting/Disconnected). Logged only on a
        // real transition, not every tick, so this can't itself become log
        // spam — the question this exists to answer is "how much earlier,
        // in practice, on a real call," not "prove it fires at all."
        if (event.connectionQuality != _lastKnownQuality) {
          debugPrint('[olive.call] ConnectionQuality '
              '${_lastKnownQuality.name} -> ${event.connectionQuality.name}');
        }
        _lastKnownQuality = event.connectionQuality;
      }
      return;
    }
  }

  /// Recovers from an unexpected room disconnect (see the RoomDisconnectedEvent
  /// branch above for the real, root-caused SDK race this exists to survive)
  /// by reconnecting with the SAME already-proven token/wsURL rather than
  /// treating any disconnect as the end of the call. Bounded to
  /// [_maxReconnectAttempts] tries with a short, increasing backoff — a real
  /// network/server failure should still surface as an honest end-of-call,
  /// not spin forever.
  Future<void> _attemptReconnect() async {
    // Set for the WHOLE attempt (cleared in every exit path below via
    // try/finally) — see _handleRoomEvent's own RoomDisconnectedEvent
    // branch for why overlapping attempts must never run concurrently.
    _reconnecting = true;
    try {
      await _attemptReconnectImpl();
    } finally {
      _reconnecting = false;
    }
  }

  Future<void> _attemptReconnectImpl() async {
    _reconnectAttempts++;
    if (mounted) setState(() => _status = _CallStatus.reconnecting);

    _qualityTicker?.cancel();
    // Deliberately NOT calling _room?.dispose() (or .disconnect()) here.
    // Real, live-hardware-confirmed finding: by the time RoomDisconnectedEvent
    // fires, the SDK's own Room object is already in the broken state that
    // caused the disconnect — calling dispose()/disconnect() on it AGAIN
    // sends it back through livekit_client's own Room.disconnect()
    // (package:livekit_client/src/core/room.dart:734), which itself awaits
    // EventsListenable.waitFor(...) for a connected-event that will now
    // NEVER arrive, throwing the exact same class of unhandled
    // TimeoutException this whole reconnect path exists to survive — just
    // from a new call site. The old Room has nothing left worth cleanly
    // releasing from here; dropping the reference and letting it be
    // garbage-collected is safer than asking a dead connection to please
    // disconnect. _listener.dispose() is a local stream-subscription
    // teardown, not a network round-trip, but it's wrapped too — nothing
    // about this SDK has earned the benefit of the doubt tonight.
    try {
      await _listener?.dispose();
    } catch (e) {
      debugPrint('[olive.call] listener dispose failed during reconnect (non-fatal): $e');
    }
    _room = null;

    final token = _lastToken;
    final wsURL = _lastWsURL;
    if (token == null || wsURL == null) {
      // Nothing real to reconnect with (shouldn't happen — _startCall
      // always sets both before a room is ever constructed — but fail
      // honestly rather than retry against nothing).
      // Fire-and-forget, deliberately — see the RoomDisconnectedEvent
      // branch's own doc comment for why: popping the Navigator must
      // never wait on a network call.
      unawaited(widget.onCallEnd?.call() ?? Future<void>.value());
      if (mounted) unawaited(Navigator.of(context).maybePop());
      return;
    }

    // Short, increasing backoff — the known SDK race resolves almost
    // immediately on retry in practice, but a brief pause avoids hammering
    // a genuinely struggling connection.
    await Future<void>.delayed(Duration(milliseconds: 800 * _reconnectAttempts));
    if (!mounted) return;

    try {
      final room = lk.Room(roomOptions: _roomOptions);
      _room = room;
      _listener = room.createListener()..listen(_handleRoomEvent);
      _qualityTicker = Timer.periodic(
        const Duration(milliseconds: _qualityTickMs), (_) => _tickQuality());
      await room.connect(wsURL, token, connectOptions: _connectOptions);
      // Audio restores unconditionally — §8.14's NEVER_SHED, the same
      // reason mic state (never gated by mode) always comes back. Video is
      // different: MASTERFILE §5.23.2's "resuming asks first" — a call that
      // reconnects itself and starts transmitting her room again because
      // the wifi came back is a privacy failure with good intentions, so a
      // camera that was ON before an UNEXPECTED drop stays off here and
      // waits for her own tap ([_awaitingResumeConsent]/resumeOffer()); a
      // camera that was already off has nothing to ask permission for.
      final hadCameraOn = _cameraEnabled;
      await room.localParticipant?.setCameraEnabled(false);
      await room.localParticipant?.setMicrophoneEnabled(_micEnabled);
      if (mounted) {
        setState(() {
          _status = _CallStatus.inCall;
          _cameraEnabled = false;
          _awaitingResumeConsent = hadCameraOn;
          // A reconnect that actually holds earns back the retry budget —
          // otherwise one flaky call early on would permanently disable
          // recovery for the rest of a long call.
          _reconnectAttempts = 0;
        });
      }
      unawaited(_publishMode());
    } catch (_) {
      // This attempt itself failed outright (never even reached
      // connected) — RoomDisconnectedEvent isn't guaranteed to fire again
      // for a connect() that never succeeded, so decide here rather than
      // wait on an event that may never come.
      if (_reconnectAttempts >= _maxReconnectAttempts) {
        unawaited(widget.onCallEnd?.call() ?? Future<void>.value());
        if (mounted) unawaited(Navigator.of(context).maybePop());
      } else {
        unawaited(_attemptReconnect());
      }
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
    // Fire-and-forget with an explicit catchError, not a bare call: a sync
    // State.dispose() can't await these, and an unhandled rejection from
    // either — this SDK's own Room.disconnect() is confirmed, live, to
    // sometimes hang and throw (see _attemptReconnectImpl's own doc
    // comment) — would otherwise escape as a genuinely unhandled exception
    // after this widget is already gone.
    unawaited(_listener?.dispose().catchError((Object e) {
      debugPrint('[olive.call] listener dispose failed on screen exit (non-fatal): $e');
      return false;
    }));
    unawaited(_room?.dispose().catchError((Object e) {
      debugPrint('[olive.call] room dispose failed on screen exit (non-fatal): $e');
      return false;
    }));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: switch (_status) {
      _CallStatus.fetchingToken => const Center(child: _Status(message: 'Finding the call…')),
      _CallStatus.joining => const Center(child: _Status(message: 'Joining…')),
      _CallStatus.reconnecting => const Center(child: _Status(message: 'Reconnecting…')),
      _CallStatus.inCall => _InCallView(
          localTrack: _localVideoTrack,
          remoteTrack: _remoteVideoTrack,
          remoteName: _remoteName,
          notice: _notice,
          isGuardian: _isGuardian,
          onHangUp: () async {
            // Set BEFORE disconnect() so the RoomDisconnectedEvent it
            // triggers is correctly read as "she hung up," not "the SDK
            // dropped us" — see _handleRoomEvent's own doc comment on why
            // that distinction is what decides whether to reconnect.
            _hangingUp = true;
            // Non-null by construction: this branch only renders once
            // _startCall() has already reached _CallStatus.inCall, which
            // only happens after _room was assigned. Wrapped defensively —
            // Room.disconnect() is confirmed, live, to sometimes hang
            // waiting on an SDK-internal event and throw (see
            // _attemptReconnectImpl's own doc comment); a genuine hang-up
            // tap must never leave her stuck on a frozen call screen just
            // because this SDK's own teardown path misbehaved. The
            // RoomDisconnectedEvent handler (_hangingUp is already true by
            // the time either fires) is what actually ends the screen
            // either way — this call's only job is to ask the room to
            // start disconnecting, not to be the thing that gets her out.
            try {
              await _room?.disconnect();
            } catch (e) {
              debugPrint('[olive.call] disconnect() threw on hang-up (non-fatal, handled): $e');
              if (context.mounted) unawaited(Navigator.of(context).maybePop());
            }
          },
          onToggleMic: () async {
            await _room?.localParticipant?.setMicrophoneEnabled(!_micEnabled);
            if (mounted) setState(() => _micEnabled = !_micEnabled);
          },
          onToggleCamera: () => _setMode(_cameraEnabled ? CallMode.audioOnly : CallMode.video),
          micEnabled: _micEnabled,
          cameraEnabled: _cameraEnabled,
          remoteMode: _remoteMode,
          awaitingResumeConsent: _awaitingResumeConsent,
          onResumeVideo: () {
            setState(() => _awaitingResumeConsent = false);
            unawaited(_setMode(CallMode.video));
          },
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
    required this.remoteMode,
    required this.awaitingResumeConsent,
    required this.onResumeVideo,
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
  /// MASTERFILE §5.23.1 — what the OTHER side's own mode is, so this view
  /// can show the real listening surface (never a black rectangle) when
  /// he's genuinely chosen voice-only, the same honest treatment a network-
  /// caused absence already gets below.
  final CallMode remoteMode;
  final bool awaitingResumeConsent;
  final VoidCallback onResumeVideo;

  @override
  Widget build(BuildContext context) => Stack(children: [
    Positioned.fill(
      child: remoteTrack != null
          ? lk.VideoTrackRenderer(remoteTrack!)
          // Never a black rectangle here — §5.23.1's NEVER_BLANK. Covers
          // every real reason there's no picture to show: he chose
          // audio-only, still connecting, or the quality ladder stepped
          // down to its own audio-only rung (§5.28) — all honestly the
          // same "nothing to look at but the call is real" state from her
          // side of the screen.
          : _ListeningSurfaceView(remoteName: remoteName, remoteMode: remoteMode),
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
    // MASTERFILE §5.23.2 — "resuming asks first." Shown only right after an
    // unexpected reconnect that found her camera on beforehand; a call she
    // never left, or one she'd already chosen to keep audio-only, never
    // sees this at all.
    if (awaitingResumeConsent)
      Align(
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Ready to carry on?',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('resumeVideoButton'),
              onPressed: onResumeVideo,
              icon: const Icon(Icons.videocam),
              label: const Text('Turn my camera back on'),
            ),
          ]),
        ),
      ),
    Positioned(
      left: 0, right: 0, bottom: 32,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _CallControlButton(
          icon: micEnabled ? Icons.mic : Icons.mic_off,
          label: micEnabled ? 'Mute' : 'Unmute',
          onPressed: onToggleMic,
        ),
        const SizedBox(width: 24),
        _CallControlButton(
          icon: Icons.call_end,
          label: 'Hang up',
          backgroundColor: Colors.redAccent,
          onPressed: onHangUp,
        ),
        const SizedBox(width: 24),
        _CallControlButton(
          icon: cameraEnabled ? Icons.videocam : Icons.videocam_off,
          label: cameraEnabled ? 'Turn camera off' : 'Turn camera on',
          onPressed: onToggleCamera,
        ),
      ]),
    ),
  ]);
}

/// MASTERFILE §5.23.1 — the listening surface. "A black rectangle is what
/// every other product shows on an audio call, and for a child it reads as
/// absence. She needs something to look at while she listens." A calm 4Hz
/// waveform — a fast one is a stimulant at bedtime — never a percentage,
/// never a spinner that implies something is wrong.
class _ListeningSurfaceView extends StatelessWidget {
  const _ListeningSurfaceView({required this.remoteName, required this.remoteMode});
  final String? remoteName;
  final CallMode remoteMode;

  @override
  Widget build(BuildContext context) {
    // The exact modeForOther() line when we genuinely know he's chosen
    // voice-only — mode only, never why (this file has no cause to leak in
    // the first place; see _publishMode's own doc comment). Falls back to
    // the honest "no picture yet" phrasing for every other real reason
    // there's nothing to show (still connecting, most plainly).
    final label = remoteMode == CallMode.audioOnly
        ? modeForOther(setMode(CallMode.audioOnly, ModeCause.chosen, '')).line
        : remoteName == null
            ? 'Waiting for the other side…'
            : '$remoteName is here — just no picture.';
    return Container(
      color: const Color(0xFF1A1A1A),
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const _CalmWaveform(),
        const SizedBox(height: 20),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ]),
    );
  }
}

/// A still, slow pulse rather than an animated meter — this is a place to
/// rest her eyes, not a status indicator she's meant to read.
class _CalmWaveform extends StatelessWidget {
  const _CalmWaveform();
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    for (final h in const [14.0, 24.0, 34.0, 24.0, 14.0])
      Container(
        width: 6, height: h, margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: Colors.white38,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
  ]);
}

class _CallControlButton extends StatelessWidget {
  const _CallControlButton({
    required this.icon, required this.label, required this.onPressed, this.backgroundColor,
  });
  final IconData icon;
  /// Mic/hang-up/camera are the three most safety-critical controls on this
  /// screen — matching every other icon-only button in this client
  /// (availability_screen.dart, handover_notes.dart, call_knock_screen.dart)
  /// in actually carrying a real label for a screen-reader user, rather
  /// than being the one place that doesn't.
  final String label;
  final Future<void> Function() onPressed;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Material(
      color: backgroundColor ?? Colors.white24,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Icon(icon, color: Colors.white, size: 28, semanticLabel: label),
        ),
      ),
    ),
  );
}
