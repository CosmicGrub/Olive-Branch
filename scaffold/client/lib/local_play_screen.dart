// OLIVE BRANCH — local play, no internet required. UNVERIFIED by
// tools/verify.sh's own automated pipeline specifically (no Flutter
// toolchain to compile Dart at all) — a distinct claim from the real
// hardware verification below, not a contradiction of it. VERIFIED on real
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
import 'package:flutter/material.dart';
import 'local_pairing.dart';
import 'play_confirm_card.dart';
import 'play_game.dart';
import 'play_notice.dart';
import 'play_session.dart';
import 'play_transport.dart';
import 'play_widgets.dart';
import 'twenty_questions_play.dart';

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
  // The conversation (envelope, order, resend, resume, the calm away line) is the shared session's
  // (play_session.dart); this screen only draws what the game (twenty_questions_play.dart) says.
  late final LocalPairingController _pairing =
      LocalPairingController(role: widget.role, displayName: widget.displayName);
  late final LocalPairingTransport _transport = LocalPairingTransport(_pairing);
  late final TwentyQuestionsPlayGame _game = TwentyQuestionsPlayGame(PlayContext(
      mode: PlayMode.pair, localSeatId: _transport.mySeat, authoritySeatId: 'b', seatIds: const ['a', 'b']));
  late final PlaySessionController _session =
      PlaySessionController(spec: twentyQuestionsSpec, game: _game, transport: _transport);

  @override
  void initState() {
    super.initState();
    _pairing.addListener(_onChanged);
    _game.addListener(_onChanged);
    _session.addListener(_onChanged);
    _session.start();
    unawaited(_pairing.start());
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _game.removeListener(_onChanged);
    _session.removeListener(_onChanged);
    _session.dispose();
    _game.dispose();
    _transport.dispose();
    _pairing.removeListener(_onChanged);
    _pairing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A hard transport error always interrupts play. Otherwise, an already-under-way game keeps rendering regardless
    // of pairing phase (a transient peer-lost blip is a calm line above it, not a different screen).
    final Widget body;
    if (_pairing.phase == PairingPhase.error) {
      body = _MessageView(
        message: _pairing.errorMessage ?? "Can't play locally right now.",
        icon: Icons.error_outline,
      );
    } else if (_session.endedForGood) {
      body = PlaySessionNotice(kind: PlayNoticeKind.ended, onLeave: () => Navigator.of(context).maybePop());
    } else if (_game.started) {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        PlayAwayBanner(session: _session),
        _PlayingView(game: _game, peerName: 'the other side', onTakeTurn: _game.next),
      ]);
    } else if (_session.hasMetPeer && _session.notice != PlayNoticeKind.none) {
      body = PlaySessionNotice(kind: _session.notice);
    } else {
      body = switch (_pairing.phase) {
        PairingPhase.found => _FoundView(amDealer: _game.ctx.isAuthority, onStart: _game.begin),
        PairingPhase.peerLost => const PlaySessionNotice(kind: PlayNoticeKind.away),
        _ => const _Status(message: 'Looking nearby…'),
      };
    }
    return PlayConfirmOverlay(pairing: _pairing, child: Scaffold(
      appBar: AppBar(title: const Text('Play nearby'), actions: [PlayFinishButton(session: _session)]),
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24), child: Center(child: body))),
    ));
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
  const _FoundView({required this.amDealer, required this.onStart});
  final bool amDealer;
  final VoidCallback onStart;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.people_alt_outlined, size: 40, color: Theme.of(context).colorScheme.primary),
    const SizedBox(height: 16),
    Text('Found someone nearby', style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 24),
    // The dealing device (the grown-up's) starts it; the other device is given the first prompt.
    if (amDealer)
      FilledButton(onPressed: onStart, child: const Text('Start twenty questions'))
    else
      Text('Getting ready…', style: Theme.of(context).textTheme.bodyLarge
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
  ]);
}

class _PlayingView extends StatelessWidget {
  const _PlayingView({required this.game, required this.peerName, required this.onTakeTurn});
  final TwentyQuestionsPlayGame game;
  final String peerName;
  final VoidCallback onTakeTurn;

  @override
  Widget build(BuildContext context) {
    final myTurn = game.iAmLeader;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(game.prompt ?? 'Think of something.', textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall),
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
