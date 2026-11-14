// OLIVE BRANCH — Piece It Together, the ad-hoc cooperative puzzle screen.
// No longer UNVERIFIED — verified by CI (a Flutter toolchain now runs for real in tools/verify.sh's
// automated pipeline — CHANGELOG v0.49.61). Network resilience & ad-hoc
// mode roadmap, Track B Option 2, ad-hoc games expansion. Builds on
// local_pairing.dart (transport) and
// together_puzzle.dart (engine) — same pattern as game_war.dart/
// game_connect4.dart/game_pictionary.dart.
//
// Pieces are small, code-drawn vector glyphs (Icons, in colouring_screen
// .dart's own Path-based-not-raster tradition), never a photo or a
// downloaded image — there is no asset pipeline here that could ever
// smuggle in a camera/gallery image.
import 'dart:async';
import 'package:flutter/material.dart';
import 'access_scope.dart' show LiveLine;
import 'design_tokens.dart';
import 'form_factors.dart' as ff show Posture, Viewport, postureFor;
import 'live_games.dart' show Side;
import 'local_pairing.dart';
import 'local_services.dart';
import 'play_confirm_card.dart';
import 'play_game.dart';
import 'play_notice.dart';
import 'play_save.dart';
import 'play_session.dart';
import 'play_transport.dart';
import 'play_widgets.dart';
import 'puzzle_play.dart';
import 'together_puzzle.dart';

/// foldTabletop's own outer padding — real-device-tested minimum,
/// deliberately NOT shared with the other 4 local-play games' own
/// identical-shaped constant: shrinking is safe, growing risks
/// reintroducing an overflow at foldTabletop's constrained ~420dp height.
/// design_tokens.dart's own header / docs/superpowers/specs/2026-09-15-
/// design-tokens-named-migration-design.md, Fix #2.
const double _foldTabletopPad = 10.0;

/// Same real per-device scale this app's other games now use — see
/// game_uno.dart's own _cardScaleFor for the identical reasoning. The
/// Wrap-based slot/piece grid here already reflows at any width on its
/// own; this scale is about legibility on a big screen, not survival on
/// a small one.
double _pieceScaleFor(ff.Posture posture) => switch (posture) {
  ff.Posture.foldCover || ff.Posture.phone || ff.Posture.tabletSmall => 1.0,
  ff.Posture.foldMain || ff.Posture.foldTabletop || ff.Posture.tabletMedium => 1.08,
  ff.Posture.tabletLarge => 1.16,
  ff.Posture.desktop || ff.Posture.dex => 1.22,
};

class GamePuzzleScreen extends StatefulWidget {
  const GamePuzzleScreen({super.key, required this.role, required this.displayName});
  final String role;
  final String displayName;

  @override
  State<GamePuzzleScreen> createState() => _GamePuzzleScreenState();
}

class _GamePuzzleScreenState extends State<GamePuzzleScreen> {
  // The conversation (envelope, order, resend, resume, the calm away line, the dealer's save) is the shared session's
  // (play_session.dart); this screen only draws what the game (puzzle_play.dart) says and sends what it is told.
  late final LocalPairingController _pairing =
      LocalPairingController(role: widget.role, displayName: widget.displayName);
  late final LocalPairingTransport _transport = LocalPairingTransport(_pairing);
  late final PuzzlePlayGame _game = PuzzlePlayGame(PlayContext(
      mode: PlayMode.pair, localSeatId: _transport.mySeat, authoritySeatId: 'b', seatIds: const ['a', 'b']));
  late final PlaySessionController _session = PlaySessionController(
      spec: puzzleSpec, game: _game, transport: _transport,
      store: LocalPlaySaveStore(LocalServices.current.area('playsave')));
  bool _celebrated = false;
  bool _offered = false;

  @override
  void initState() {
    super.initState();
    _pairing.addListener(_onPairingChanged);
    _game.addListener(_onPairingChanged);
    _session.addListener(_onPairingChanged);
    _session.start();
    unawaited(_pairing.start());
    unawaited(_offerSavedGame());
  }

  /// A dealer with a saved puzzle is asked whether to carry on with it (play_save.dart).
  Future<void> _offerSavedGame() async {
    if (!await _session.hasSavedGame() || !mounted) return;
    _offered = true;
    final carryOn = await askResumeSavedGame(context, 'Puzzle together');
    _offered = false;
    if (carryOn) {
      await _session.resumeSavedGame();
    } else {
      await _session.discardSavedGame();
    }
    if (mounted) _onPairingChanged();
  }

  void _onPairingChanged() {
    if (!mounted) return;
    // The dealer opens the puzzle the moment the other device is found (unless it is still being asked about a save).
    if (_pairing.phase == PairingPhase.found && !_offered) _game.begin();
    setState(() {});
  }

  @override
  void dispose() {
    _game.removeListener(_onPairingChanged);
    _session.removeListener(_onPairingChanged);
    _session.dispose();
    _game.dispose();
    _transport.dispose();
    _pairing.removeListener(_onPairingChanged);
    _pairing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Measured once, outside any scroll view — see game_uno.dart's own
    // build() for why this must happen above a LayoutBuilder, not inside
    // one nested in something scrollable.
    return LayoutBuilder(builder: (context, constraints) {
      final posture = ff.postureFor(ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight));
      final state = _game.state;
      final Widget body;
      if (_pairing.phase == PairingPhase.error) {
        body = _MessageView(message: _pairing.errorMessage ?? "Can't play locally right now.",
          icon: Icons.error_outline);
      } else if (_session.endedForGood) {
        body = PlaySessionNotice(kind: PlayNoticeKind.ended, onLeave: () => Navigator.of(context).maybePop());
      } else if (state != null) {
        // The puzzle stays on screen while the other device is away, with one calm line above it.
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          PlayAwayBanner(session: _session),
          PuzzleView(
            state: state, mySide: _game.mySide, peerName: 'the other side',
            onPlace: _game.place, celebrated: _celebrated,
            onCelebrate: () => setState(() => _celebrated = true),
            pieceScale: _pieceScaleFor(posture),
          ),
          if (_game.finished) PlayRematchBar(session: _session),
        ]);
      } else if (_session.hasMetPeer && _session.notice != PlayNoticeKind.none) {
        body = PlaySessionNotice(kind: _session.notice);
      } else {
        body = switch (_pairing.phase) {
          PairingPhase.peerLost => const PlaySessionNotice(kind: PlayNoticeKind.away),
          _ => const _Status(message: 'Looking nearby…'),
        };
      }
      final outerPad = posture == ff.Posture.foldTabletop ? _foldTabletopPad : AppSpacing.lg;
      return PlayConfirmOverlay(pairing: _pairing, child: Scaffold(
        appBar: AppBar(title: const Text('Piece it together'), actions: [PlayFinishButton(session: _session)]),
        // SingleChildScrollView, not a bare Center — see game_uno.dart's own
        // build() for why: real-device testing at foldTabletop's ~420dp
        // height overflowed there. Same child_home.dart/care_note.dart
        // scroll convention.
        body: SafeArea(child: SingleChildScrollView(
          padding: EdgeInsets.all(outerPad),
          child: Center(child: body),
        )),
      ));
    });
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

const Map<String, IconData> _pieceGlyphs = {
  'cow': Icons.pets, 'barn': Icons.home_work, 'tractor': Icons.agriculture,
  'sun': Icons.wb_sunny, 'tree': Icons.park, 'fence': Icons.fence,
};

class PuzzleView extends StatelessWidget {
  const PuzzleView({super.key, required this.state, required this.mySide, required this.peerName,
    required this.onPlace, required this.celebrated, required this.onCelebrate, this.pieceScale = 1.0});
  final TogetherPuzzleState state;
  final Side mySide;
  final String peerName;
  final void Function(String pieceId, String slotId) onPlace;
  final bool celebrated;
  final VoidCallback onCelebrate;
  final double pieceScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final def = puzzleFor(state.puzzleId)!;
    final myTurn = state.mover == mySide;
    final remaining = def.pieces.where((p) => !state.placedPieces.contains(p.id)).toList();
    final slotSize = 72 * pieceScale;

    return Column(mainAxisSize: MainAxisSize.min, children: [
      LiveLine(child: Text(
        state.solved ? 'Good job — you did it together!' : myTurn ? 'Your turn to place a piece' : 'Waiting for $peerName…',
        style: theme.textTheme.titleMedium, textAlign: TextAlign.center,
      )),
      const SizedBox(height: 16),
      // Slots grid — each slot individually meets the 64dp touch-target
      // floor (§8.4/§8.11.3), a harder constraint here than chrome buttons
      // since these ARE the actual drag targets a small child's finger
      // needs to hit. Wrap already reflows at any real width on its own;
      // pieceScale (a real per-device multiplier, never below 1.0 — see
      // _pieceScaleFor's own doc comment) is purely a legibility bump on
      // a bigger screen, not a survival mechanism on a small one.
      Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
        for (final slot in def.slots)
          DragTarget<String>(
            onWillAcceptWithDetails: (details) => myTurn && !state.placedPieces.contains(details.data)
                && pieceFor(def, details.data)?.correctSlotId == slot.id,
            onAcceptWithDetails: (details) => onPlace(details.data, slot.id),
            builder: (context, candidates, rejected) {
              final placedPiece = def.pieces.where((p) => p.correctSlotId == slot.id && state.placedPieces.contains(p.id)).firstOrNull;
              final highlighted = candidates.isNotEmpty;
              return Semantics(
                container: true, excludeSemantics: true, label: slot.label,
                value: placedPiece != null ? '${placedPiece.label}, placed' : 'empty',
                child: Container(
                width: slotSize, height: slotSize,
                decoration: BoxDecoration(
                  color: placedPiece != null
                      ? theme.colorScheme.primaryContainer
                      : highlighted ? theme.colorScheme.secondaryContainer : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outline, width: 1.5),
                ),
                alignment: Alignment.center,
                child: placedPiece != null
                    ? Icon(_pieceGlyphs[placedPiece.id], size: 34 * pieceScale)
                    : Text(slot.label, style: theme.textTheme.labelSmall, textAlign: TextAlign.center),
              ));
            },
          ),
      ]),
      const SizedBox(height: 24),
      if (myTurn && remaining.isNotEmpty && !state.solved) ...[
        Text('Drag a piece to its spot', style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
          for (final piece in remaining)
            // Dragging is not possible without sight and a steady finger, so a screen
            // reader's activate puts the piece in its own spot: the same move a correct
            // drag makes, and nothing a wrong drag could.
            Semantics(
              container: true, excludeSemantics: true, button: true,
              label: '${piece.label} piece', hint: 'Double tap to put it in its spot',
              onTap: () => onPlace(piece.id, piece.correctSlotId),
              child: Draggable<String>(
                data: piece.id,
                feedback: _PieceChip(piece: piece, elevated: true, scale: pieceScale),
                childWhenDragging: Opacity(opacity: 0.3, child: _PieceChip(piece: piece, scale: pieceScale)),
                child: _PieceChip(piece: piece, scale: pieceScale),
              )),
        ]),
      ],
    ]);
  }
}

class _PieceChip extends StatelessWidget {
  const _PieceChip({required this.piece, this.elevated = false, this.scale = 1.0});
  final PuzzlePiece piece;
  final bool elevated;
  final double scale;
  @override
  Widget build(BuildContext context) => Container(
    width: 64 * scale, height: 64 * scale,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(12),
      boxShadow: elevated ? [const BoxShadow(color: Colors.black26, blurRadius: 8)] : null,
    ),
    alignment: Alignment.center,
    child: Icon(_pieceGlyphs[piece.id], size: 32 * scale),
  );
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
