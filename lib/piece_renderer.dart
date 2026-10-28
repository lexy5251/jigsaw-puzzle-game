// Piece rendering overview:
// 1. The photo is cut once, at load time: every piece gets its own small
//    image — the photo clipped by that piece's knob outline, plus a thin
//    outline stroke so pieces read as separate on the board.
// 2. Tabs stick out past a piece's base cell, so each piece image includes a
//    margin ("bleed") around the cell. PuzzlePiece keeps using the base cell
//    for its position, size, snapping and saves; only the drawing is bigger,
//    shifted up-left by the bleed.
// 3. Pre-cutting costs a moment on load but keeps per-frame drawing cheap:
//    no clip paths while dragging.

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';

import 'piece_shapes.dart';

/// One piece's drawable: the shaped image and how far it extends past the
/// piece's base cell on each axis.
class ShapedPieceImage {
  const ShapedPieceImage({required this.sprite, required this.bleed});

  final Sprite sprite;

  /// Offset of the base cell's top-left inside [sprite] — equal on both
  /// axes and identical for every piece of one puzzle.
  final Vector2 bleed;

  /// Called by the owning game once neither board nor tray needs this image.
  void dispose() => sprite.image.dispose();
}

/// Cuts [source] into columns x rows shaped pieces.
///
/// World units equal image pixels in this game, so the returned sprites are
/// drawn 1:1 with no scaling. The caller owns the returned images; [source]
/// remains owned by its caller.
Future<List<ShapedPieceImage>> rasterizePieces({
  required ui.Image source,
  required int columns,
  required int rows,
  required PieceShapeGrid shapes,
}) async {
  final cellWidth = source.width / columns;
  final cellHeight = source.height / rows;
  // Room for the farthest a tab can stick out, plus 1px for the stroke's
  // antialiased edge.
  final bleed =
      (knobOverhangFraction * min(cellWidth, cellHeight)).ceilToDouble() + 1;

  final outline = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = const ui.Color(0x59000000);

  Future<ShapedPieceImage> cutPiece(int index) async {
    final row = index ~/ columns;
    final column = index % columns;
    final path = buildPiecePath(
      shape: shapes.shapeAtIndex(index),
      width: cellWidth,
      height: cellHeight,
    ).shift(ui.Offset(bleed, bleed));

    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..clipPath(path)
      // Draw the whole photo positioned so this piece's cell lands just
      // inside the bleed margin; the clip keeps only the piece's outline.
      ..drawImage(
        source,
        ui.Offset(bleed - column * cellWidth, bleed - row * cellHeight),
        ui.Paint(),
      )
      ..drawPath(path, outline);

    final picture = recorder.endRecording();
    try {
      final pieceImage = await picture.toImage(
        (cellWidth + 2 * bleed).ceil(),
        (cellHeight + 2 * bleed).ceil(),
      );
      return ShapedPieceImage(
        sprite: Sprite(pieceImage),
        bleed: Vector2.all(bleed),
      );
    } finally {
      picture.dispose();
    }
  }

  return Future.wait(
    [for (var index = 0; index < columns * rows; index++) cutPiece(index)],
    // A failed cut must also release the images made by the successful cuts.
    cleanUp: (piece) => piece.dispose(),
  );
}
