// The bonus board: the current gift painting assembling itself in the
// Collection tab. Every gift board is a 25-piece (5x5) puzzle — the same
// cut as the smallest playable size, so it needs no explanation. Each
// earned piece reveals its jigsaw-shaped part of the real artwork (owner's
// pick: the picture becomes guessable as it fills); pieces appear in a
// seeded scattered order so the subject stays a mystery longer, and
// unearned pieces stay canvas-ground with only their outlines drawn.

import 'package:flutter/material.dart';

import 'bonus_track.dart';
import 'piece_shapes.dart';
import 'puzzle_catalog.dart';
import 'studio_surfaces.dart';
import 'studio_theme.dart';

/// The board's grid; columns x rows must equal [bonusBoardPieces].
const _boardColumns = 5;
const _boardRows = 5;

/// Plain-words line under the board. Shared with tests so the copy cannot
/// drift. "New painting", not "puzzle": replays and repeat sizes of a
/// finished painting earn nothing (the first-finish rule).
const bonusBoardHintText =
    'Every new painting you finish adds a piece — '
    'a 3-day streak adds one more.';

/// "N of 25 pieces" — the visible count and the board's semantics label.
String bonusBoardProgressText(int earnedPieces) =>
    '$earnedPieces of $bonusBoardPieces pieces';

/// The Collection tab's hero card: kicker, the assembling picture in its
/// frame, the piece count, and the plain-words earning hint.
class BonusBoardCard extends StatelessWidget {
  const BonusBoardCard({
    super.key,
    required this.image,
    required this.earnedPieces,
  });

  final PuzzleImage image;

  /// Pieces already revealed; always below [bonusBoardPieces] (a full
  /// board unlocks and the next one takes its place).
  final int earnedPieces;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PaintedCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'BONUS PUZZLE',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: StudioColors.structureDark,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            identifier: 'bonus-board-${image.id}',
            // The title stays out of the label on purpose: the picture is a
            // surprise until it assembles, for screen-reader players too.
            label: 'Bonus picture: ${bonusBoardProgressText(earnedPieces)}',
            excludeSemantics: true,
            child: AspectRatio(
              aspectRatio: 1,
              child: FramedArt(
                child: _BonusReveal(image: image, earnedPieces: earnedPieces),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            bonusBoardProgressText(earnedPieces),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 2),
          Text(
            bonusBoardHintText,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// The picture under the frame: ground backdrop, one image layer clipped to
/// each earned piece, and every piece outline stroked on top so the jigsaw
/// cut reads on earned and waiting pieces alike.
class _BonusReveal extends StatelessWidget {
  const _BonusReveal({required this.image, required this.earnedPieces});

  final PuzzleImage image;
  final int earnedPieces;

  /// The same seeded cut and reveal order on every visit — a board that
  /// re-cut or re-shuffled itself between visits would read as broken.
  int get _seed => shapeSeedForKey('bonus-board.${image.id}');

  @override
  Widget build(BuildContext context) {
    final revealed = revealOrderFor(_seed).take(earnedPieces).toSet();
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: StudioColors.ground),
        // Each layer draws the full image clipped to its piece, so a knob
        // reaching into a neighbor cell shows exactly that neighbor's bit
        // of artwork.
        for (final piece in revealed)
          ClipPath(
            clipper: _BonusPieceClipper(pieceIndex: piece, seed: _seed),
            child: Image.asset(
              image.assetPath,
              fit: BoxFit.cover,
              cacheWidth: TiltedPhotoCard.thumbnailCacheWidth,
              // No title fallback here — a failed decode must not spoil
              // the surprise; the ground simply stays bare.
              errorBuilder: (context, _, _) => const SizedBox.shrink(),
            ),
          ),
        IgnorePointer(
          child: CustomPaint(
            painter: _PieceOutlinePainter(revealed: revealed, seed: _seed),
          ),
        ),
      ],
    );
  }
}

/// The order pieces appear in: a seeded shuffle of the board's cells, so
/// early pieces land scattered across the picture instead of filling it
/// row by row (which would hand over the subject too early). Stable across
/// sessions — same xorshift as the piece cutter, for the same reason
/// dart:math Random is banned for anything persistent-feeling.
@visibleForTesting
List<int> revealOrderFor(int seed) {
  // Shares the cutter's generator and shuffle on purpose: this order is
  // persistent-feeling (a board that re-shuffled between visits would read
  // as broken), and seededShuffle draws exactly like the inline loop this
  // replaced — existing boards keep their reveal order.
  final order = [for (var i = 0; i < bonusBoardPieces; i++) i];
  seededShuffle(order, Xorshift32(seed));
  return order;
}

/// Builds the outline of piece [index] on the 5x5 board filling [size].
Path _piecePath(Size size, int index, int seed) {
  final grid = PieceShapeGrid.generate(
    columns: _boardColumns,
    rows: _boardRows,
    seed: seed,
  );
  final cellWidth = size.width / _boardColumns;
  final cellHeight = size.height / _boardRows;
  return buildPiecePath(
    shape: grid.shapeAtIndex(index),
    width: cellWidth,
    height: cellHeight,
  ).shift(
    Offset(
      (index % _boardColumns) * cellWidth,
      (index ~/ _boardColumns) * cellHeight,
    ),
  );
}

class _BonusPieceClipper extends CustomClipper<Path> {
  const _BonusPieceClipper({required this.pieceIndex, required this.seed});

  final int pieceIndex;
  final int seed;

  @override
  Path getClip(Size size) => _piecePath(size, pieceIndex, seed);

  @override
  bool shouldReclip(_BonusPieceClipper oldClipper) =>
      oldClipper.pieceIndex != pieceIndex || oldClipper.seed != seed;
}

class _PieceOutlinePainter extends CustomPainter {
  const _PieceOutlinePainter({required this.revealed, required this.seed});

  final Set<int> revealed;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    // Waiting pieces get a soft ink wash so they read as empty slots, not
    // bare mat; every piece gets its outline so the cut is visible.
    final slotFill = Paint()
      ..color = StudioColors.ink.withValues(alpha: 0.06);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = StudioColors.ink.withValues(alpha: 0.18);
    for (var piece = 0; piece < bonusBoardPieces; piece++) {
      final path = _piecePath(size, piece, seed);
      if (!revealed.contains(piece)) {
        canvas.drawPath(path, slotFill);
      }
      canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(_PieceOutlinePainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.revealed.length != revealed.length;
}
