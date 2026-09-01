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
import 'form_factors.dart' as ff show Posture, Viewport, postureFor;
import 'live_games.dart' show Side, auditLiveView;
import 'local_pairing.dart';
import 'together_puzzle.dart';

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
  late final LocalPairingController _pairing =
      LocalPairingController(role: widget.role, displayName: widget.displayName);
  StreamSubscription<LocalTurnPayload>? _turnSub;

  TogetherPuzzleState? _state;
  bool _celebrated = false;

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

  void _startIfNeeded() {
    if (_state != null) return;
    setState(() => _state = newPuzzle('farmyard'));
  }

  Future<void> _tryPlace(String pieceId, String slotId) async {
    final current = _state;
    if (current == null || _mySide != current.mover) return;
    final result = placePiece(current, _mySide, pieceId, slotId);
    if (!result.accepted) return; // a wrong slot is rejected here, never sent, never recorded
    setState(() => _state = result.state);
    final payload = <String, dynamic>{
      'kind': 'piecePuzzle', 'puzzleId': result.state.puzzleId,
      'mover': result.state.mover == Side.a ? 'a' : 'b',
      'placedPieces': result.state.placedPieces.toList(),
      'solved': result.state.solved,
    };
    final audit = auditLiveView(payload);
    if (!audit.ok) {
      debugPrint('game_puzzle: refusing to send a payload with forbidden keys: ${audit.leaks}');
      return;
    }
    await _pairing.sendTurn(payload);
  }

  void _handleIncomingTurn(LocalTurnPayload payload) {
    if (payload['kind'] != 'piecePuzzle') return;
    final current = _state ?? newPuzzle('farmyard');
    final placedRaw = payload['placedPieces'];
    final moverRaw = payload['mover'];
    if (placedRaw is! List || (moverRaw != 'a' && moverRaw != 'b')) return;
    final placed = <String>[];
    for (final p in placedRaw) {
      if (p is! String) return;
      placed.add(p);
    }
    final merged = mergeIncoming(current, placedPieces: placed, mover: moverRaw == 'a' ? Side.a : Side.b);
    if (mounted) setState(() => _state = merged);
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
    // Measured once, outside any scroll view — see game_uno.dart's own
    // build() for why this must happen above a LayoutBuilder, not inside
    // one nested in something scrollable.
    return LayoutBuilder(builder: (context, constraints) {
      final posture = ff.postureFor(ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight));
      final state = _state;
      final Widget body;
      if (_pairing.phase == PairingPhase.error) {
        body = _MessageView(message: _pairing.errorMessage ?? "Can't play locally right now.",
          icon: Icons.error_outline);
      } else if (_pairing.phase == PairingPhase.found || state != null) {
        _startIfNeeded();
        body = _PuzzleView(
          state: _state!, mySide: _mySide, peerName: _pairing.peer?.name ?? 'the other side',
          onPlace: _tryPlace, celebrated: _celebrated,
          onCelebrate: () => setState(() => _celebrated = true),
          pieceScale: _pieceScaleFor(posture),
        );
      } else {
        body = switch (_pairing.phase) {
          PairingPhase.searching => const _Status(message: 'Looking nearby…'),
          PairingPhase.peerLost =>
            _MessageView(message: _pairing.errorMessage!, icon: Icons.wifi_off_outlined),
          PairingPhase.found => throw StateError('handled above'),
          PairingPhase.error => throw StateError('handled above'),
        };
      }
      final outerPad = posture == ff.Posture.foldTabletop ? 10.0 : 16.0;
      return Scaffold(
        appBar: AppBar(title: const Text('Piece it together')),
        // SingleChildScrollView, not a bare Center — see game_uno.dart's own
        // build() for why: real-device testing at foldTabletop's ~420dp
        // height overflowed there. Same child_home.dart/care_note.dart
        // scroll convention.
        body: SafeArea(child: SingleChildScrollView(
          padding: EdgeInsets.all(outerPad),
          child: Center(child: body),
        )),
      );
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

class _PuzzleView extends StatelessWidget {
  const _PuzzleView({required this.state, required this.mySide, required this.peerName,
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
      Text('${state.placedPieces.length} of ${def.pieces.length} placed together',
        style: theme.textTheme.bodyMedium),
      const SizedBox(height: 8),
      Text(
        state.solved ? 'Good job — you did it together!' : myTurn ? 'Your turn to place a piece' : 'Waiting for $peerName…',
        style: theme.textTheme.titleMedium, textAlign: TextAlign.center,
      ),
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
              return Container(
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
              );
            },
          ),
      ]),
      const SizedBox(height: 24),
      if (myTurn && remaining.isNotEmpty && !state.solved) ...[
        Text('Drag a piece to its spot', style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
          for (final piece in remaining)
            Draggable<String>(
              data: piece.id,
              feedback: _PieceChip(piece: piece, elevated: true, scale: pieceScale),
              childWhenDragging: Opacity(opacity: 0.3, child: _PieceChip(piece: piece, scale: pieceScale)),
              child: _PieceChip(piece: piece, scale: pieceScale),
            ),
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
