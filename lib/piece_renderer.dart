// Piece rendering overview:
// 1. The photo is cut once, at load time: every piece gets its own small
//    image — the photo clipped by that piece's knob outline (clean-flat
//    style, no painted decoration) — plus a small baked contact shadow.
//    Per-frame drawing stays a single cheap sprite blit.
// 2. Tabs stick out past a piece's base cell, so each piece image includes a
//    margin ("bleed") around the cell. PuzzlePiece keeps using the base cell
//    for its position, size, snapping and saves; only the drawing is bigger,
//    shifted up-left by the bleed.
// 3. Every body pixel stays INSIDE the outline: pieces sit flush in joined
//    chunks, so one pixel of overshoot would land on a neighbour's face.
//    Drop shadows (lifted drag shadow, baked resting contact shadow) are the
//    only things drawn outside, and the game paints them on separate layers
//    below the bodies.
// 4. Dragged pieces re-render the body live from the original photo with a
//    vector clip, keeping the outline sharp while the camera is zoomed in.

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';

import 'piece_shapes.dart';

// ——— Clean-flat look: the owner-tunable knobs. ———
// The photo runs edge-to-edge to the cut; the ONLY depth cue is the soft
// shadow under unplaced pieces. Sizes are in decoration units (≈ screen px
// on a resting piece); colors are ARGB.

/// Contact shadow under a resting piece (renderShadow's non-lifted look):
/// mostly downward, soft and deliberately quiet — just enough to lift the
/// piece off the board.
const restShadowOffset = ui.Offset(0.3, 1.6);
const restShadowColor = ui.Color(0x22403329);
const restShadowBlur = 1.1;

/// Soft darkening just inside the cut, uniform around the silhouette — the
/// face rounding over the edge. Zero the color's alpha to turn it off.
const pieceEdgeShadeColor = ui.Color(0x4A352A1E);
const pieceEdgeShadeWidth = 2.2;
const pieceEdgeShadeBlur = 1.0;

/// Very faint light catch on the upper-left inner edge, giving the rounding
/// a light direction. Zero the color's alpha to turn it off.
const pieceEdgeLightColor = ui.Color(0x42FFFFFF);
const pieceEdgeLightWidth = 1.0;
const pieceEdgeLightBlur = 0.6;

/// One piece's drawables: the shaped image, its baked contact shadow, and
/// how far they extend past the piece's base cell on each axis.
class ShapedPieceImage {
  const ShapedPieceImage({
    required this.sprite,
    required this.restShadow,
    required this.shadowPad,
    required this.bleed,
    required this.artwork,
  });

  final Sprite sprite;
  final PieceArtwork artwork;

  /// Baked contact shadow, at half resolution — a pure blur upscales
  /// invisibly and quarters the memory. Its box is the sprite box grown by
  /// [shadowPad] on every side, so the blur is never clipped where a tab
  /// reaches the sprite edge.
  final Sprite restShadow;

  /// How far [restShadow]'s box extends past the sprite box on each side,
  /// in source pixels. Blit sites must offset/grow by this.
  final double shadowPad;

  /// Offset of the base cell's top-left inside [sprite] — equal on both
  /// axes and identical for every piece of one puzzle.
  final Vector2 bleed;

  /// Called by the owning game once neither board nor tray needs this image.
  void dispose() {
    sprite.image.dispose();
    restShadow.image.dispose();
  }
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

  /// Draws the piece body — the photo, edge-to-edge to the cut, with a soft
  /// rounded-edge shade — mapping the full sprite box onto [bounds].
  /// Everything stays inside the outline (strokes are clipped to their inner
  /// half), so joined pieces sit flush. Decoration is measured in local
  /// canvas units; board callers compensate for camera zoom.
  void render(
    ui.Canvas canvas, {
    required ui.Rect bounds,
    double decorationScale = 1,
    ui.Paint? photoPaint,
  }) {
    final unit = _applyBoundsTransform(canvas, bounds, decorationScale);
    canvas.clipPath(outline);
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
    // The 3D cue: a blurred darkening just inside the cut, identical around
    // knobs and straight runs (uniform + blurred = never reads as an inked
    // line, and nothing is shifted so it can never halo), plus a faint
    // directional light catch on the upper-left inner edge.
    canvas.drawPath(
      outline,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = pieceEdgeShadeWidth * unit
        ..color = pieceEdgeShadeColor
        ..maskFilter = ui.MaskFilter.blur(
          ui.BlurStyle.normal,
          pieceEdgeShadeBlur * unit,
        ),
    );
    canvas.drawPath(
      outline.shift(ui.Offset(0.4 * unit, 0.5 * unit)),
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = pieceEdgeLightWidth * unit
        ..color = pieceEdgeLightColor
        ..maskFilter = ui.MaskFilter.blur(
          ui.BlurStyle.normal,
          pieceEdgeLightBlur * unit,
        ),
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
      outline.shift(
        lifted
            ? ui.Offset(0.3 * unit, 2.8 * unit)
            : ui.Offset(restShadowOffset.dx * unit, restShadowOffset.dy * unit),
      ),
      ui.Paint()
        ..color = lifted ? const ui.Color(0x45403329) : restShadowColor
        ..maskFilter = ui.MaskFilter.blur(
          ui.BlurStyle.normal,
          (lifted ? 1.5 : restShadowBlur) * unit,
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
  // Room for the farthest a tab can stick out, plus 1px for the clip's
  // antialiased edge.
  final bleed =
      (knobOverhangFraction * min(cellWidth, cellHeight)).ceilToDouble() + 1;

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

    final spriteBounds = ui.Rect.fromLTWH(
      0,
      0,
      spriteWidth.toDouble(),
      spriteHeight.toDouble(),
    );
    // A tab tip reaches to ~1px of the sprite edge, so the shadow box must
    // grow past it by the shadow's full reach (offset plus ~3 sigma of blur)
    // or the blur gets clipped flat below down/right-pointing tabs.
    final shadowPad =
        ((max(restShadowOffset.dx.abs(), restShadowOffset.dy.abs()) +
                    3 * restShadowBlur) *
                decorationUnit)
            .ceilToDouble();

    Future<ui.Image> bake(
      double scale,
      ui.Size size,
      void Function(ui.Canvas) draw,
    ) async {
      final recorder = ui.PictureRecorder();
      draw(ui.Canvas(recorder)..scale(scale));
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(
          (size.width * scale).ceil(),
          (size.height * scale).ceil(),
        );
      } finally {
        picture.dispose();
      }
    }

    // Bake the body once; per-frame board drawing is a sprite blit.
    final pieceImage = await bake(
      1,
      spriteBounds.size,
      (canvas) => artwork.render(
        canvas,
        bounds: spriteBounds,
        decorationScale: decorationUnit,
      ),
    );
    try {
      // The contact shadow is pure blur, so half resolution upscales
      // invisibly and quarters its memory.
      final shadowImage = await bake(
        0.5,
        ui.Size(
          spriteBounds.width + 2 * shadowPad,
          spriteBounds.height + 2 * shadowPad,
        ),
        (canvas) {
          canvas.translate(shadowPad, shadowPad);
          artwork.renderShadow(
            canvas,
            bounds: spriteBounds,
            decorationScale: decorationUnit,
          );
        },
      );
      return ShapedPieceImage(
        sprite: Sprite(pieceImage),
        restShadow: Sprite(shadowImage),
        shadowPad: shadowPad,
        bleed: Vector2.all(bleed),
        artwork: artwork,
      );
    } catch (_) {
      // Future.wait's cleanUp only disposes completed pieces; a failed
      // shadow bake must release its own body image.
      pieceImage.dispose();
      rethrow;
    }
  }

  return Future.wait(
    [for (var index = 0; index < columns * rows; index++) cutPiece(index)],
    // A failed cut must also release the images made by the successful cuts.
    cleanUp: (piece) => piece.dispose(),
  );
}
