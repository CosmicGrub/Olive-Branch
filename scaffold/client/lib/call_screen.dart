// OLIVE BRANCH — real-time call screen. UNVERIFIED on real devices in this
// build (the engines ran on hardware in earlier eras; this screen's move onto
// the provider seam is covered by flutter analyze/test and the owner's two-
// device plan). §5.19/§5.23 the call. MASTERFILE §16.2 #6, REVERSED a third
// time (2026-11-09): self-hosted Jitsi is the default call provider, LiveKit
// stays selectable.
//
// THIS FILE KNOWS NO MEDIA ENGINE. It depends only on call_provider.dart (the
// interface, the grant, the calm wording) plus the registry that picks an
// engine from the server's grant (call_provider_registry.dart). It imports
// neither livekit_client nor jitsi_meet_flutter_sdk, and tests/
// call_ui_imports_test.dart keeps it that way at source level. Which engine
// carries a call is the SERVER's decision, carried in the grant's `provider`.
//
// What stays here, provider-agnostic: the dialing/joining/reconnecting
// surfaces, the degradation ladder (degradation_banner.dart, unchanged) fed by
// whatever condition the engine reports, audio-only as a choice (§5.23.1),
// "resuming asks first" (§5.23.2), the end-of-call callback, and the calm
// states. Wording is audience-aware: soft for the child, plain for an adult
// (callUnavailableLine); a raw exception never reaches either of them.
//
// Two shapes of live call:
//  - an engine that draws its own screen (Jitsi's native Activity): this
//    screen rests behind it with a calm "on a call" surface and a hang-up;
//  - an engine that gives us video surfaces (LiveKit): [InCallView] below.
//
// The one thing the two devices still need to agree on is which room to join.
// That coordination is the server's (packages/session-runtime/src/rooms.ts:
// I1 room name never guessable, I4 authorization gate), reached through
// OliveApi.startCall / joinCall, or in dev through
// tools/local-call-room-server.mjs (LiveKit only).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'call_modes.dart';
import 'call_provider.dart';
import 'call_provider_registry.dart';
import 'degradation_banner.dart';
import 'form_factors.dart' as ff;
import 'kiosk_channel.dart';
import 'tabletop_split.dart';

/// LOCAL DEV/TEST ONLY — tools/local-call-room-server.mjs (LiveKit tokens).
/// Not a production endpoint. Loopback on purpose (`adb reverse tcp:8787
/// tcp:8787` per device; a hardcoded LAN address goes stale).
const devRoomServerBase = 'http://127.0.0.1:8787';

/// 'ivy' is the only child identity any real call site uses (child_home.dart,
/// call_knock_screen.dart's answer path); every other value — today only
/// 'dad' — is a guardian. guardian_more.dart's real call-start route already
/// refuses a child principal outright (child_cannot_start_call), so 'who' and
/// "which side of the ladder can this device leave kiosk lock" agree in every
/// real path. Top-level so a widget test can exercise it directly.
bool isGuardianWho(String who) => who != 'ivy';

class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.who,
    required this.displayName,
    this.knownGrant,
    this.knownToken,
    this.knownWsURL,
    this.onCallEnd,
    this.initialMode = CallMode.video,
    this.accentColor,
    this.kiosk,
    this.providerFactory,
  });

  /// 'dad' or 'ivy' — matches local-call-room-server.mjs's fixed identities.
  final String who;
  final String displayName;

  /// Her real curated colour (§8.6), for the dialing/joining moment only.
  final Color? accentColor;

  /// MASTERFILE §5.23.1 — audio-only as a CHOICE, not a punishment. Set by
  /// whichever real answer she tapped (call_knock_screen.dart's "Answer" vs
  /// "Just talking") or the equivalent choice on the originating side.
  final CallMode initialMode;

  /// The already-minted grant for this call: the decoded response of
  /// `POST /v1/children/:childId/calls` (a guardian starting) or of
  /// `.../calls/:sessionId/join` (the callee answering), parsed with
  /// [CallGrant.fromJson]. It says which engine to use. Null (with no
  /// [knownToken] either) means the dev-room-server fetch path.
  final CallGrant? knownGrant;

  /// LiveKit-only shorthand for [knownGrant], kept so every existing call site
  /// and test that already passes a token + project URL keeps working: the
  /// pair is exactly `CallGrant.livekit(token, wsURL)`. [knownGrant] wins.
  final String? knownToken;
  final String? knownWsURL;

  /// Fires once, right before this screen navigates away after a real call
  /// that really connected — never when the call never started. A
  /// caller-supplied callback so this screen stays decoupled from OliveApi
  /// (mirrors guardian_more.dart's own onCallStarted seam).
  final Future<void> Function()? onCallEnd;

  /// Injectable for widget tests; defaults to the real platform channel.
  final KioskChannel? kiosk;

  /// Injectable engine factory for tests (a [FakeCallProvider]); defaults to
  /// the registry, which picks the engine from the grant.
  final CallProviderFactory? providerFactory;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

enum _Stage { fetching, joining, live, unavailable }

class _CallScreenState extends State<CallScreen> {
  CallProvider? _provider;
  StreamSubscription<CallViewState>? _sub;
  _Stage _stage = _Stage.fetching;
  CallUnavailableReason _reason = CallUnavailableReason.unreachable;
  CallViewState _view = const CallViewState();
  bool _finished = false;
  // Bumped on each attempt so a late result from an abandoned attempt (Try
  // again, or leaving the screen) can never act on the new state.
  int _attempt = 0;

  // The ladder (degradation_banner.dart) is unchanged; it is fed whatever
  // condition the engine reports. An engine with no report stays "good".
  StreamState _stream = newStream();
  StreamNotice? _notice;
  Timer? _qualityTicker;
  static const _qualityTickMs = 250; // matches degradation_banner.dart's own _tickMs

  bool get _isGuardian => isGuardianWho(widget.who);

  @override
  void initState() {
    super.initState();
    _startCall();
  }

  Future<CallGrant> _fetchGrant() async {
    if (widget.knownGrant != null) return widget.knownGrant!;
    if (widget.knownToken != null && widget.knownWsURL != null) {
      return CallGrant.livekit(token: widget.knownToken!, wsURL: widget.knownWsURL!, displayName: widget.displayName);
    }
    final client = HttpClient();
    try {
      final uri = Uri.parse('$devRoomServerBase/room?who=${widget.who}');
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 6));
      final response = await request.close().timeout(const Duration(seconds: 6));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw CallUnavailableException(
          response.statusCode == 503 ? CallUnavailableReason.providerOff : CallUnavailableReason.refused,
          'room server answered ${response.statusCode}');
      }
      return CallGrant.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } finally {
      client.close();
    }
  }

  CallUnavailableException _asUnavailable(Object e) {
    if (e is CallUnavailableException) return e;
    if (e is SocketException || e is TimeoutException || e is HttpException) {
      return CallUnavailableException(CallUnavailableReason.unreachable, '$e');
    }
    if (e is FormatException) return CallUnavailableException(CallUnavailableReason.refused, e.message);
    return CallUnavailableException(CallUnavailableReason.unreachable, '$e');
  }

  Future<void> _teardownProvider() async {
    _qualityTicker?.cancel();
    _qualityTicker = null;
    // Not awaited: a cancel() on the engine's broadcast stream is not worth
    // blocking a retry on (and under FakeAsync it can outlive a pump).
    unawaited(_sub?.cancel());
    _sub = null;
    final p = _provider;
    _provider = null;
    if (p != null) unawaited(p.dispose());
  }

  Future<void> _startCall() async {
    final attempt = ++_attempt;
    await _teardownProvider();
    _finished = false;
    _stream = newStream();
    _notice = null;
    if (!mounted) return;
    setState(() {
      _stage = _Stage.fetching;
      _view = const CallViewState();
    });
    try {
      final grant = await _fetchGrant();
      if (!mounted || attempt != _attempt) return;
      final provider = (widget.providerFactory ??
          (g) => defaultCallProviderFor(g, kiosk: widget.kiosk))(grant);
      _provider = provider;
      _sub = provider.states.listen(_onView);
      _qualityTicker = Timer.periodic(
        const Duration(milliseconds: _qualityTickMs), (_) => _tickQuality());
      setState(() => _stage = _Stage.joining);
      await provider.join(grant, CallJoinOptions(
        displayName: widget.displayName, mode: widget.initialMode, isGuardian: _isGuardian));
      if (!mounted || attempt != _attempt) return;
      // The engine may already have said "connected" while join() ran.
      _onView(provider.state);
    } catch (e) {
      if (!mounted || attempt != _attempt) return;
      final u = _asUnavailable(e);
      debugPrint('[olive.call] call did not start: ${u.reason} ${u.detail ?? ''}');
      await _teardownProvider();
      if (!mounted) return;
      setState(() {
        _reason = u.reason;
        _stage = _Stage.unavailable;
      });
    }
  }

  void _onView(CallViewState v) {
    if (!mounted || _finished) return;
    if (v.phase == CallPhase.ended) {
      if (v.everConnected) {
        _finished = true;
        // Fire-and-forget, deliberately: popping the Navigator must never wait
        // on a network call, and a failed end-call POST must never strand the
        // user on a screen that already knows the call is over (record-keeping
        // only; no server-side media revocation happens here, a disclosed,
        // separate gap).
        widget.onCallEnd?.call();
        unawaited(Navigator.of(context).maybePop());
      } else {
        // The call never really started: calm, and nothing to record.
        unawaited(_teardownProvider());
        setState(() {
          _reason = CallUnavailableReason.unreachable;
          _stage = _Stage.unavailable;
        });
      }
      return;
    }
    setState(() {
      _view = v;
      if (v.phase == CallPhase.connected || v.phase == CallPhase.reconnecting) _stage = _Stage.live;
    });
  }

  /// Runs every _qualityTickMs off a real Timer; evaluate()/noticeFor()/
  /// markTold() are degradation_banner.dart's, completely unmodified.
  void _tickQuality() {
    final result = evaluate(_stream, StreamTick(_view.condition, _qualityTickMs));
    if (result.changed != StreamChange.none) {
      _provider?.applyQuality(result.state.quality);
    }
    final notice = noticeFor(result.state);
    if (!mounted) return;
    _stream = notice != null ? markTold(result.state) : result.state;
    // Rebuild only when there is something new to show; a quiet call must not
    // repaint four times a second for nothing.
    if (notice != null) setState(() => _notice = notice);
  }

  @override
  void dispose() {
    _qualityTicker?.cancel();
    unawaited(_sub?.cancel());
    final p = _provider;
    if (p != null) unawaited(p.dispose());
    super.dispose();
  }

  Future<void> _hangUp() async {
    final p = _provider;
    if (p == null) {
      if (mounted) unawaited(Navigator.of(context).maybePop());
      return;
    }
    // The engine's own ended phase (through _onView) is what actually leaves
    // the screen; a hang-up tap must never leave her stuck if teardown misbehaves.
    try {
      await p.leave();
    } catch (e) {
      debugPrint('[olive.call] leave threw (non-fatal): $e');
      if (mounted) unawaited(Navigator.of(context).maybePop());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    // A LayoutBuilder purely so InCallView can be told whether the ambient
    // posture is foldTabletop; every other stage renders exactly as before.
    body: LayoutBuilder(builder: (context, constraints) {
      final tabletop = ff.postureFor(
          ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight)) ==
        ff.Posture.foldTabletop;
      switch (_stage) {
        case _Stage.fetching:
          return Center(child: _Status(message: callingLine(widget.displayName), color: widget.accentColor));
        case _Stage.joining:
          return Center(child: _Status(message: joiningLine(widget.displayName), color: widget.accentColor));
        case _Stage.unavailable:
          return Center(child: _UnavailableState(
            message: callUnavailableLine(_reason, isGuardian: _isGuardian),
            onRetry: _startCall,
          ));
        case _Stage.live:
          final p = _provider;
          if (p == null) return const SizedBox.shrink();
          if (_view.phase == CallPhase.reconnecting) {
            return Center(child: _Status(message: reconnectingLine, color: widget.accentColor));
          }
          if (p.rendersOwnScreen) {
            // The engine's native screen is on top; this is what rests behind
            // it (and what she lands on if she comes back to the app mid-call).
            return Center(child: _OnACallSurface(
              displayName: widget.displayName, onHangUp: _hangUp, color: widget.accentColor));
          }
          return InCallView(
            tabletop: tabletop,
            localVideo: _view.hasLocalVideo ? p.buildLocalVideo() : null,
            remoteVideo: _view.hasRemoteVideo ? p.buildRemoteVideo() : null,
            remoteName: _view.remoteName,
            notice: _notice,
            isGuardian: _isGuardian,
            onHangUp: _hangUp,
            onToggleMic: () => p.setMicrophoneEnabled(!_view.micEnabled),
            onToggleCamera: () => p.setCameraEnabled(!_view.cameraEnabled),
            micEnabled: _view.micEnabled,
            cameraEnabled: _view.cameraEnabled,
            remoteMode: _view.remoteMode,
            awaitingResumeConsent: _view.awaitingResumeConsent,
            onResumeVideo: () => unawaited(p.setCameraEnabled(true)),
          );
      }
    }),
  );
}

class _Status extends StatelessWidget {
  const _Status({required this.message, this.color});
  final String message;
  /// Her real curated colour, when the caller resolved one. Plain white when null.
  final Color? color;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    CircularProgressIndicator(color: color ?? Colors.white),
    const SizedBox(height: 16),
    Text(message, textAlign: TextAlign.center, style: TextStyle(color: color ?? Colors.white)),
  ]);
}

/// Calm, never alarming: a soft icon (not a red hang-up glyph), the audience-
/// aware line, a way to try again and a way back.
class _UnavailableState extends StatelessWidget {
  const _UnavailableState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.call, size: 40, color: Colors.white54),
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

/// The resting surface behind an engine that draws its own call screen.
class _OnACallSurface extends StatelessWidget {
  const _OnACallSurface({required this.displayName, required this.onHangUp, this.color});
  final String displayName;
  final Future<void> Function() onHangUp;
  final Color? color;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.call, size: 40, color: color ?? Colors.white70),
    const SizedBox(height: 12),
    Text("You're on a call with $displayName.",
      textAlign: TextAlign.center, style: TextStyle(color: color ?? Colors.white)),
    const SizedBox(height: 20),
    _CallControlButton(
      icon: Icons.call_end, label: 'Hang up', backgroundColor: Colors.redAccent, onPressed: onHangUp),
  ]);
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
/// Public (not `_InCallView`, its name through v0.49.69) specifically so a
/// widget test can construct it directly, the same reason `isGuardianWho`
/// above is a top-level function rather than a private method on
/// [_CallScreenState] — call_screen_test.dart can never reach `_CallStatus
/// .inCall` for real (no live LiveKit connection exists in a test sandbox),
/// so this is the only way to exercise the foldTabletop split below at all.
class InCallView extends StatelessWidget {
  const InCallView({
    super.key,
    required this.localVideo,
    required this.remoteVideo,
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
    this.tabletop = false,
  });

  /// Engine-supplied video surfaces (null when there is no picture to show).
  /// call_screen.dart knows no media engine; the provider builds these.
  final Widget? localVideo;
  final Widget? remoteVideo;
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
  /// Intuitivism pass, sub-project 3c, Part 2 — true only when
  /// `CallScreen`'s own new LayoutBuilder reads `Posture.foldTabletop`.
  /// Defaults to false so every existing call site (none pass this yet)
  /// keeps its exact prior Stack-overlay rendering, unconditionally.
  final bool tabletop;

  /// The real remote view — video, or the honest §5.23.1 NEVER_BLANK
  /// listening surface — crossfaded between the two, not hard-cut. Real
  /// bug, found by review: this used to be a bare ternary swap, duplicated
  /// at both this widget's own call sites (tabletop and non-tabletop),
  /// with no transition at all on a live-call surface a child is actively
  /// watching whenever the quality ladder steps down to audio-only
  /// (§5.28) or a track genuinely arrives/drops. Same 120ms crossfadeMs
  /// convention as motion_rules.dart / DegradationBanner's own fix.
  Widget _remoteView() => AnimatedSwitcher(
    duration: const Duration(milliseconds: 120),
    transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
    // KeyedSubtree, not a key passed directly into either branch's own
    // constructor — sidesteps needing to know whether the engine's own
    // video widget itself exposes a `key` param, while
    // still giving AnimatedSwitcher the distinct identity it needs to
    // detect "this is a different child" between the two states.
    child: remoteVideo != null
      ? KeyedSubtree(key: const ValueKey('remoteVideo'), child: remoteVideo!)
      : KeyedSubtree(key: const ValueKey('remoteListening'),
          child: _ListeningSurfaceView(remoteName: remoteName, remoteMode: remoteMode)),
  );

  @override
  Widget build(BuildContext context) {
    if (tabletop) {
      // Arguably the single most natural real-world tabletop use case on a
      // Fold5 (the design spec's own words): propped up hands-free on a
      // table during a call. Video above the hinge, call controls below it
      // — a real Column split via TabletopSplit, not the Stack overlay
      // below (which stays completely untouched for every other posture).
      // TabletopSplit puts this half in a scroll view (unbounded height), so it
      // needs an explicit height: just under half the screen, above the hinge.
      final Widget videoArea = SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.45,
        child: Stack(fit: StackFit.expand, children: [
        Positioned.fill(child: _remoteView()),
        DegradationBanner(notice: notice),
        if (localVideo != null)
          Positioned(
            top: 16, right: 16, width: 110, height: 150,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: localVideo!,
            ),
          ),
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
      ]));
      final Widget controlsRow = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
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
      ]);
      return TabletopSplit(viewing: videoArea, controls: Center(child: controlsRow));
    }
    // StackFit.expand: DegradationBanner is the one NON-positioned child; with
    // the default loose fit it sized this whole Stack to 0x0 and clipped the
    // video and the controls away (found by tapping 'Mute' in a widget test
    // for the first time; the LiveKit-era view was never run on a device).
    return Stack(fit: StackFit.expand, children: [
    Positioned.fill(child: _remoteView()),
    DegradationBanner(notice: notice),
    if (localVideo != null)
      Positioned(
        top: 16, right: 16, width: 110, height: 150,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: localVideo!,
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
