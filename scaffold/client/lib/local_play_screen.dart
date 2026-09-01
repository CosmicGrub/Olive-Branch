// OLIVE BRANCH — local play, no internet required. VERIFIED on real
// hardware (2026-08-30): a real Fold5 (dad) and a real Galaxy Tab (ivy),
// both on the same LAN, found each other via mDNS and played real rounds of
// Twenty Questions end to end — Round 1 through Round 2, each side's own
// screen updating from the *other* physical device's real HTTP POST, no
// LiveKit, no cloud, no internet path involved at any point (this file's
// own test entry, main_live_local_play_test.dart, has zero backend
// dependency to begin with). Two real bugs surfaced by that exact run and
// fixed, not simulated: local_session.dart's server was binding to a single
// guessed network interface, which on real hardware lost a race against an
// active VPN tunnel and left the real Wi-Fi address unreachable (see that
// file's own header); and this file's own peer-lost recovery never cleared
// _peer, so a real, reproducible mDNS TXT-record hiccup left the screen
// stuck on "stepped out of range" forever even once the peer re-resolved
// seconds later. NOT yet verified: the specific "home internet path
// genuinely unavailable" scenario (WAN deliberately cut, or a
// captive-portal network) — everything proven so far shows this transport
// needs no WAN, not that it survives one actively failing. Network
// resilience & ad-hoc mode roadmap, Track B Option 2 — the real, end-to-end
// proof that local discovery (local_discovery.dart) + a local turn
// transport (local_session.dart) actually plays a real game between two
// real devices with zero LiveKit, zero cloud, zero internet at all.
//
// REFACTORED (2026-08-30, ad-hoc games expansion) onto local_pairing.dart's
// LocalPairingController — the mDNS-discovery-and-handoff state machine
// this file used to own directly now lives there, shared by every new game
// screen this expansion adds (War, Connect 4, Uno, a drawing game, a
// puzzle) instead of being copied five more times. RE-VERIFIED on the same
// real Fold5 + Galaxy Tab pair after the refactor (2026-08-30): pairing,
// sending, receiving, and round advancement all still work exactly as
// before (see local_pairing.dart's own header for the full account,
// including a real peer-lost/re-found cycle hit during that exact
// verification run). This class is the reference pattern every new game
// screen in this expansion should follow.
// The one real behavior note worth stating explicitly: the peer-lost
// resume fix used to be expressed as the pairing phase jumping straight to
// a game-specific "playing" state on re-found. LocalPairingController
// deliberately has no such state (see its own header) — so build() below
// expresses the identical resume-not-restart behavior itself, simply: show
// the game view whenever a local _session already exists, regardless of
// pairing phase, UNLESS pairing has hit a real error (which still takes
// priority and interrupts play, exactly as before).
//
// Deliberately narrow, matching this whole codebase's own "prove the
// pattern with one real thing, don't half-build ten" discipline (compare
// live_games.dart's own header on its own unwired-Phase-2 status): ONE
// game, Twenty Questions, reusing live_games.dart's own LiveSession/
// nextRound()/DECKS verbatim — that logic has no camera/audio coupling at
// all (confirmed by having written it this same session), so reusing it
// here for a local-only, no-call context is honest reuse, not a stretch.
//
// NEVER a media path — see local_session.dart's own header for why that
// line is load-bearing, not a style note.
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'live_games.dart';
import 'local_pairing.dart';

class LocalPlayScreen extends StatefulWidget {
  const LocalPlayScreen({super.key, required this.role, required this.displayName});

  /// 'dad' or 'ivy' — the same real identity vocabulary call_screen.dart
  /// already uses. Determines this device's [Side] in the shared
  /// [LiveSession]: 'ivy' is always [Side.a], matching every other real
  /// call site's own fixed convention (isGuardianWho's own doc comment).
  final String role;
  final String displayName;

  @override
  State<LocalPlayScreen> createState() => _LocalPlayScreenState();
}

class _LocalPlayScreenState extends State<LocalPlayScreen> {
  late final LocalPairingController _pairing =
      LocalPairingController(role: widget.role, displayName: widget.displayName);
  StreamSubscription<LocalTurnPayload>? _turnSub;

  LiveSession? _session;
  final _rand = Random();

  Side get _mySide => _pairing.mySide;

  @override
  void initState() {
    super.initState();
    _pairing.addListener(_onPairingChanged);
    _turnSub = _pairing.incomingTurns.listen(_handleIncomingTurn);
    unawaited(_pairing.start());
  }

  void _onPairingChanged() {
    if (mounted) setState(() {});
  }

  void _startGame() {
    final result = startLive(LiveKind.twentyQuestions, Side.b, DateTime.now().toIso8601String(), _rand);
    if (!result.ok || result.session == null) return;
    setState(() => _session = result.session);
    if (_mySide == Side.b) unawaited(_sendCurrentState());
  }

  /// Only the LEADER draws a new prompt and sends it — the other device
  /// never independently draws (see this file's own header on why each
  /// side keeping its own deck is an accepted, minor imperfection rather
  /// than something this pass tries to fully solve).
  Future<void> _takeMyTurn() async {
    final session = _session;
    if (session == null || session.leader != _mySide) return;
    setState(() => _session = nextRound(session, _rand));
    await _sendCurrentState();
  }

  Future<void> _sendCurrentState() async {
    final session = _session;
    if (session == null) return;
    await _pairing.sendTurn({
      'currentPrompt': session.currentPrompt,
      'rounds': session.rounds,
      'leader': session.leader == Side.a ? 'a' : 'b',
    });
  }

  void _handleIncomingTurn(LocalTurnPayload payload) {
    final leader = payload['leader'] == 'a' ? Side.a : Side.b;
    final existing = _session;
    final updated = LiveSession(
      kind: LiveKind.twentyQuestions,
      startedAt: existing?.startedAt ?? DateTime.now().toIso8601String(),
      leader: leader,
      deck: existing?.deck ?? newDeck(LiveKind.twentyQuestions, _rand),
      currentPrompt: payload['currentPrompt'] as String?,
      rounds: payload['rounds'] as int? ?? 0,
      connection: ConnectionQuality.good,
      degradedAt: null,
    );
    if (mounted) setState(() => _session = updated);
  }

  @override
  void dispose() {
    unawaited(_turnSub?.cancel());
    _pairing.removeListener(_onPairingChanged);
    _pairing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    // A hard transport error always interrupts play. Otherwise, an
    // already-under-way session keeps rendering regardless of pairing
    // phase — the real fix for a transient peer-lost blip (see this file's
    // and local_pairing.dart's own headers) — and only an in-progress-less
    // screen defers to the raw pairing phase.
    final Widget body;
    if (_pairing.phase == PairingPhase.error) {
      body = _MessageView(
        message: _pairing.errorMessage ?? "Can't play locally right now.",
        icon: Icons.error_outline,
      );
    } else if (session != null) {
      body = _PlayingView(
        session: session, mySide: _mySide, peerName: _pairing.peer?.name ?? 'the other side',
        onTakeTurn: _takeMyTurn);
    } else {
      body = switch (_pairing.phase) {
        PairingPhase.searching => const _Status(message: 'Looking nearby…'),
        PairingPhase.found => _FoundView(peerName: _pairing.peer!.name, onStart: _startGame),
        PairingPhase.peerLost =>
          _MessageView(message: _pairing.errorMessage!, icon: Icons.wifi_off_outlined),
        PairingPhase.error => throw StateError('handled above'),
      };
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Play nearby')),
      body: SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Center(child: body))),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    const CircularProgressIndicator(),
    const SizedBox(height: 16),
    Text(message, style: Theme.of(context).textTheme.bodyLarge),
  ]);
}

class _FoundView extends StatelessWidget {
  const _FoundView({required this.peerName, required this.onStart});
  final String peerName;
  final VoidCallback onStart;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.people_alt_outlined, size: 40, color: Theme.of(context).colorScheme.primary),
    const SizedBox(height: 16),
    Text('Found $peerName nearby', style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 24),
    FilledButton(onPressed: onStart, child: const Text('Start twenty questions')),
  ]);
}

class _PlayingView extends StatelessWidget {
  const _PlayingView({required this.session, required this.mySide, required this.peerName, required this.onTakeTurn});
  final LiveSession session;
  final Side mySide;
  final String peerName;
  final VoidCallback onTakeTurn;

  @override
  Widget build(BuildContext context) {
    final myTurn = session.leader == mySide;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(session.currentPrompt ?? 'Think of something.', textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text('Round ${session.rounds + 1}', style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 24),
      if (myTurn)
        FilledButton(onPressed: onTakeTurn, child: const Text('Next round'))
      else
        Text('Waiting for $peerName…', style: Theme.of(context).textTheme.bodyLarge
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]);
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.message, required this.icon});
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
    const SizedBox(height: 16),
    Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
  ]);
}
