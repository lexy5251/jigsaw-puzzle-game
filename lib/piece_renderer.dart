// Piece rendering overview:
// 1. The photo is cut once, at load time: every piece gets its own small
//    image — the decorated piece body (cardboard rim, photo, bevels, thin
//    outline stroke) clipped by that piece's knob outline. Per-frame drawing
//    stays a single cheap sprite blit.
// 2. Tabs stick out past a piece's base cell, so each piece image includes a
//    margin ("bleed") around the cell. PuzzlePiece keeps using the base cell
//    for its position, size, snapping and saves; only the drawing is bigger,
//    shifted up-left by the bleed.
// 3. Every body decoration stays INSIDE the outline: pieces sit flush in
//    joined chunks, so one pixel of overshoot would land on a neighbour's
//    face. The lifted drop shadow is the only thing drawn outside, and the
//    game paints it on a separate layer below every dragged body.
// 4. Dragged pieces re-render the body live from the original photo with a
//    vector clip, keeping the outline sharp while the camera is zoomed in.

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';

import 'piece_shapes.dart';

/// One piece's drawable: the shaped image and how far it extends past the
/// piece's base cell on each axis.
class ShapedPieceImage {
  const ShapedPieceImage({
    required this.sprite,
    required this.bleed,
    required this.artwork,
  });

  final Sprite sprite;
  final PieceArtwork artwork;

  /// Offset of the base cell's top-left inside [sprite] — equal on both
  /// axes and identical for every piece of one puzzle.
  final Vector2 bleed;

  /// Called by the owning game once neither board nor tray needs this image.
  void dispose() => sprite.image.dispose();
}

/// Original photo and vector outline for a piece, borrowing the game's source
/// image. No extra textures are needed for high-density tray previews.
class PieceArtwork {
  PieceArtwork({
    required this.source,
    required this.sourceCell,
    required this.outline,
    required this.bleed,
    required this.imageSize,
    required this.decorationUnit,
  });

  final ui.Image source;
  final ui.Rect sourceCell;
  final ui.Path outline;
  final double bleed;
  final ui.Size imageSize;

  /// The decoration unit the sprite was baked with, in source pixels.
  final double decorationUnit;

  /// The [render] decorationScale that reproduces the baked rim thickness
  /// when this artwork is drawn into [bounds] — live previews stay as thick
  /// as the resting board pieces they mirror, at any preview size.
  double bakedDecorationScale(ui.Rect bounds) =>
      decorationUnit *
      min(bounds.width / imageSize.width, bounds.height / imageSize.height);

  /// Draws the piece body — cardboard rim, photo, bevels — mapping the full
  /// sprite box onto [bounds]. Everything stays inside the outline: joined
  /// pieces sit flush, so overshoot would paint on a neighbour's face.
  /// Decoration is measured in local canvas units; board callers compensate
  /// for camera zoom so the cardboard does not become a thick slab when the
  /// player zooms in.
  void render(
    ui.Canvas canvas, {
    required ui.Rect bounds,
    double decorationScale = 1,
    ui.Paint? photoPaint,
  }) {
    final unit = _applyBoundsTransform(canvas, bounds, decorationScale);
    canvas.clipPath(outline);

    // Cardboard under the photo: the photo is inset up-left, so a thin band
    // of board shows along the lower-right inner edge — reads as thickness
    // without leaving the outline.
    canvas.drawPath(outline, ui.Paint()..color = const ui.Color(0xFF92785A));
    canvas.save();
    canvas.clipPath(outline.shift(ui.Offset(-0.2 * unit, -1.1 * unit)));
    canvas.drawImage(
      source,
      -sourceCell.topLeft,
      photoPaint ??
          // Mipmapped sampling: anything below 1:1 aliases the photo's bright
          // pixels into a visible light edge on device (the old tray bug).
          (ui.Paint()
            ..filterQuality = ui.FilterQuality.medium
            ..isAntiAlias = true),
    );
    canvas.restore();

    // Shifted strokes clipped to the face catch only the inward-facing rim:
    // light from the upper left, a fine shaded bevel on the lower right.
    canvas.drawPath(
      outline.shift(ui.Offset(0.45 * unit, 0.55 * unit)),
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 0.85 * unit
        ..color = const ui.Color(0x60FFFFFF),
    );
    canvas.drawPath(
      outline.shift(ui.Offset(-0.4 * unit, -0.5 * unit)),
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 0.75 * unit
        ..color = const ui.Color(0x45453524),
    );
    canvas.restore();
  }

  /// Draws the soft drop shadow of the outline. Kept separate from [render]
  /// so the game can paint ALL dragged pieces' shadows below ALL their
  /// bodies — a dragged chunk must never shade its own members.
  void renderShadow(
    ui.Canvas canvas, {
    required ui.Rect bounds,
    double decorationScale = 1,
    bool lifted = false,
  }) {
    final unit = _applyBoundsTransform(canvas, bounds, decorationScale);
    canvas.drawPath(
      outline.shift(ui.Offset(0.3 * unit, (lifted ? 2.8 : 1.5) * unit)),
      ui.Paint()
        ..color = ui.Color(lifted ? 0x45403329 : 0x30403329)
        ..maskFilter = ui.MaskFilter.blur(
          ui.BlurStyle.normal,
          (lifted ? 1.5 : 0.7) * unit,
        ),
    );
    canvas.restore();
  }

  /// Saves the canvas, maps the sprite box onto [bounds], and returns the
  /// decoration unit. Callers must canvas.restore() when done.
  double _applyBoundsTransform(
    ui.Canvas canvas,
    ui.Rect bounds,
    double decorationScale,
  ) {
    final scaleX = bounds.width / imageSize.width;
    final scaleY = bounds.height / imageSize.height;
    canvas.save();
    canvas.translate(bounds.left, bounds.top);
    canvas.scale(scaleX, scaleY);
    canvas.translate(bleed, bleed);
    return decorationScale / min(scaleX, scaleY);
  }
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
    ..strokeWidth = 1.0
    ..color = const ui.Color(0x33423528);

  // Decorations are baked at source-pixel scale, so size them from the cell:
  // proportional pieces look the same on a 24-piece and a 216-piece board.
  final decorationUnit = max(1.0, min(cellWidth, cellHeight) / 40);
  final spriteWidth = (cellWidth + 2 * bleed).ceil();
  final spriteHeight = (cellHeight + 2 * bleed).ceil();

  Future<ShapedPieceImage> cutPiece(int index) async {
    final row = index ~/ columns;
    final column = index % columns;
    final outlinePath = buildPiecePath(
      shape: shapes.shapeAtIndex(index),
      width: cellWidth,
      height: cellHeight,
    );
    final artwork = PieceArtwork(
      source: source,
      sourceCell: ui.Rect.fromLTWH(
        column * cellWidth,
        row * cellHeight,
        cellWidth,
        cellHeight,
      ),
      outline: outlinePath,
      bleed: bleed,
      imageSize: ui.Size(spriteWidth.toDouble(), spriteHeight.toDouble()),
      decorationUnit: decorationUnit,
    );

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    // Bake the decorated body once; per-frame board drawing is a sprite blit.
    artwork.render(
      canvas,
      bounds: ui.Rect.fromLTWH(
        0,
        0,
        spriteWidth.toDouble(),
        spriteHeight.toDouble(),
      ),
      decorationScale: decorationUnit,
    );
    canvas.drawPath(outlinePath.shift(ui.Offset(bleed, bleed)), outline);

    final picture = recorder.endRecording();
    try {
      final pieceImage = await picture.toImage(spriteWidth, spriteHeight);
      return ShapedPieceImage(
        sprite: Sprite(pieceImage),
        bleed: Vector2.all(bleed),
        artwork: artwork,
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
