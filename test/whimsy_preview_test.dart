// Dev tool, not a test: renders the whimsy-piece look to docs/*.png so the
// figures can be judged on a real catalog photo before a device build.
// Skipped unless WHIMSY_PREVIEW=1:
//   WHIMSY_PREVIEW=1 flutter test test/whimsy_preview_test.dart
//
// Three sheets:
// - whimsy-shapes-preview.png   every figure at zoom and board scale
// - whimsy-assembly-preview.png star + heart clusters assembled flush
//                               (the seam judgement)
// - whimsy-tray-preview.png     tray thumbnails vs today's cut (the one
//                               visible tradeoff: the grown bleed shrinks
//                               the photo content in equal boxes)

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/piece_renderer.dart';
import 'package:jigsaw_puzzle/piece_shapes.dart';
import 'package:jigsaw_puzzle/puzzle_logic.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';
import 'package:jigsaw_puzzle/whimsy_plan.dart';
import 'package:jigsaw_puzzle/whimsy_shapes.dart';

import 'test_helpers.dart';

void main() {
  final enabled = previewEnabled('WHIMSY_PREVIEW');
  const photoAsset = 'assets/images/landscapes/alpine_lakes_panorama.webp';

  Future<List<ShapedPieceImage>> cutPhoto(
    ui.Image source, {
    required int columns,
    required int rows,
    required WhimsyPlan plan,
  }) => rasterizePieces(
    source: source,
    columns: columns,
    rows: rows,
    shapes: PieceShapeGrid.generate(
      columns: columns,
      rows: rows,
      seed: 11,
      whimsyCells: plan.cellIndexes,
    ),
    whimsyPlan: plan,
  );

  // Shadow first, then body — the game's stacking for unplaced pieces.
  void drawPiece(
    Canvas canvas,
    ShapedPieceImage piece,
    Offset at,
    double targetWidth,
  ) {
    final artwork = piece.artwork;
    final srcSize = piece.sprite.srcSize;
    final bounds = Rect.fromLTWH(
      at.dx,
      at.dy,
      targetWidth,
      targetWidth * srcSize.y / srcSize.x,
    );
    final scale = artwork.bakedDecorationScale(bounds);
    artwork.renderShadow(canvas, bounds: bounds, decorationScale: scale);
    artwork.render(canvas, bounds: bounds, decorationScale: scale);
  }

  void drawLabel(Canvas canvas, String label, Offset at, {double size = 30}) {
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: 'Nunito',
          fontWeight: FontWeight.w800,
          fontSize: size,
          color: StudioColors.ink,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, at);
    text.dispose();
  }

  testWidgets('render the whimsy figure sheet', (tester) async {
    await tester.runAsync(() async {
      await loadStudioFonts();
      final source = await decodeAssetImage(photoAsset);
      addTearDown(source.dispose);

      // 12x12 with 12 hand-placed whimsy cells (rows 1/4/7/10 x cols 1/4/7:
      // pairwise Manhattan distance >= 3), one per figure in enum order.
      const cells = [13, 16, 19, 49, 52, 55, 85, 88, 91, 121, 124, 127];
      final plan = WhimsyPlan({
        for (var i = 0; i < WhimsyShape.values.length; i++)
          cells[i]: WhimsyShape.values[i],
      });
      final pieces = await cutPhoto(source, columns: 12, rows: 12, plan: plan);
      addTearDown(() {
        for (final piece in pieces) {
          piece.dispose();
        }
      });

      const tileWidth = 370.0;
      const tileHeight = 320.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 40 + 4 * tileWidth, 60 + 3 * tileHeight),
        Paint()..color = StudioColors.board,
      );
      for (var i = 0; i < WhimsyShape.values.length; i++) {
        final shape = WhimsyShape.values[i];
        final origin = Offset(
          40 + (i % 4) * tileWidth,
          40 + (i ~/ 4) * tileHeight,
        );
        // Zoomed judgement next to board scale (a 12x12 cell on a phone).
        drawPiece(canvas, pieces[cells[i]], origin, 200);
        drawPiece(canvas, pieces[cells[i]], origin + const Offset(220, 50), 100);
        drawLabel(canvas, shape.name, origin + const Offset(0, 210));
      }
      final picture = recorder.endRecording();
      final sheet = await picture.toImage(
        (40 + 4 * tileWidth).ceil(),
        (60 + 3 * tileHeight).ceil(),
      );
      picture.dispose();
      addTearDown(sheet.dispose);
      await writePreviewPng(sheet, 'docs/whimsy-shapes-preview.png');
    });
  }, skip: !enabled);

  testWidgets('render the whimsy assembly sheet', (tester) async {
    await tester.runAsync(() async {
      await loadStudioFonts();
      final source = await decodeAssetImage(photoAsset);
      addTearDown(source.dispose);

      // A 3x3 solved region around a center whimsy. 'last piece' holds the
      // figure lifted above its hole — the moment before the drop — because
      // a fully locked region is deliberately seamless and shows nothing by
      // itself. The locked panel beside it is the seam judgement: any gap
      // or bright sliver around the figure would show against its twin.
      Future<ui.Image> clusterPanel(
        WhimsyShape shape, {
        required bool lastPiece,
      }) async {
        const scale = 0.8;
        final plan = WhimsyPlan({12: shape});
        final pieces = await cutPhoto(source, columns: 5, rows: 5, plan: plan);
        try {
          final cell = source.width / 5;
          // Bleed varies per piece (flap neighbors carry the big one): pad
          // the panel for the largest and place each sprite by its own.
          final maxBleed = pieces
              .map((piece) => piece.bleed.x)
              .reduce((a, b) => a > b ? a : b);
          final panelSide = (3 * cell + 2 * maxBleed) * scale;
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawRect(
            Rect.fromLTWH(0, 0, panelSide, panelSide),
            Paint()..color = StudioColors.board,
          );
          Rect boundsFor(int row, int column, ShapedPieceImage piece) {
            final srcSize = piece.sprite.srcSize;
            return Rect.fromLTWH(
              ((column - 1) * cell + maxBleed - piece.bleed.x) * scale,
              ((row - 1) * cell + maxBleed - piece.bleed.y) * scale,
              srcSize.x * scale,
              srcSize.y * scale,
            );
          }

          void drawFlush(ShapedPieceImage piece, Rect bounds) {
            piece.artwork.render(
              canvas,
              bounds: bounds,
              decorationScale: piece.artwork.bakedDecorationScale(bounds),
            );
          }

          for (var row = 1; row <= 3; row++) {
            for (var column = 1; column <= 3; column++) {
              final index = row * 5 + column;
              if (index == 12) continue; // the figure is drawn last
              drawFlush(pieces[index], boundsFor(row, column, pieces[index]));
            }
          }
          final whimsy = pieces[12];
          var bounds = boundsFor(2, 2, whimsy);
          if (lastPiece) {
            // Hover the figure up-right of its hole, with the drag shadow,
            // like a piece carried the instant before it snaps. Far enough
            // that the near-cell-sized figure doesn't cover its own hole.
            bounds = bounds.shift(
              Offset(0.62 * cell * scale, -0.56 * cell * scale),
            );
            whimsy.artwork.renderShadow(
              canvas,
              bounds: bounds,
              decorationScale: whimsy.artwork.bakedDecorationScale(bounds),
              lifted: true,
            );
          }
          drawFlush(whimsy, bounds);
          final picture = recorder.endRecording();
          try {
            return await picture.toImage(panelSide.ceil(), panelSide.ceil());
          } finally {
            picture.dispose();
          }
        } finally {
          for (final piece in pieces) {
            piece.dispose();
          }
        }
      }

      await composePreviewSheet([
        (
          await clusterPanel(WhimsyShape.star, lastPiece: true),
          'star · last piece',
        ),
        (
          await clusterPanel(WhimsyShape.star, lastPiece: false),
          'star · locked',
        ),
        (
          await clusterPanel(WhimsyShape.heart, lastPiece: true),
          'heart · last piece',
        ),
        (
          await clusterPanel(WhimsyShape.heart, lastPiece: false),
          'heart · locked',
        ),
      ], 'docs/whimsy-assembly-preview.png');
    });
  }, skip: !enabled);

  testWidgets('render the whimsy tray sheet', (tester) async {
    await tester.runAsync(() async {
      await loadStudioFonts();
      final source = await decodeAssetImage(photoAsset);
      addTearDown(source.dispose);

      // Same four 10x10 pieces from both cuts: the whimsy cell (44), its
      // flap neighbor above (34), a plain interior piece (57) and an edge
      // piece (3). Equal thumbnail boxes at the tray's height cap, rendered
      // at 3x for a device-pixel look — the photo content shrinks in the
      // whimsy cut because every sprite box carries the grown bleed.
      const indexes = [44, 34, 57, 3];
      const thumbHeight = 3 * trayThumbnailHeightCap;

      Future<ui.Image> trayRow(WhimsyPlan plan) async {
        final pieces = await cutPhoto(source, columns: 10, rows: 10, plan: plan);
        try {
          final aspect =
              pieces.first.sprite.srcSize.x / pieces.first.sprite.srcSize.y;
          final thumbWidth = thumbHeight * aspect;
          final width = 32 + indexes.length * (thumbWidth + 16);
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawRect(
            Rect.fromLTWH(0, 0, width, thumbHeight + 32),
            Paint()..color = StudioColors.tray,
          );
          for (var i = 0; i < indexes.length; i++) {
            drawPiece(
              canvas,
              pieces[indexes[i]],
              Offset(16 + i * (thumbWidth + 16), 16),
              thumbWidth,
            );
          }
          final picture = recorder.endRecording();
          try {
            return await picture.toImage(
              width.ceil(),
              (thumbHeight + 32).ceil(),
            );
          } finally {
            picture.dispose();
          }
        } finally {
          for (final piece in pieces) {
            piece.dispose();
          }
        }
      }

      await composePreviewSheet([
        (await trayRow(const WhimsyPlan({44: WhimsyShape.heart})), 'whimsy cut'),
        (await trayRow(WhimsyPlan.none), 'today'),
      ], 'docs/whimsy-tray-preview.png');
    });
  }, skip: !enabled);
}
