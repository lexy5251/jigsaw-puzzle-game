// Dev tool, not a test: renders the current piece look to
// docs/piece-look-preview.png so the style can be judged as an image before
// a device build. Skipped unless PIECE_PREVIEW=1:
//   PIECE_PREVIEW=1 flutter test test/piece_look_preview_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/piece_renderer.dart';
import 'package:jigsaw_puzzle/piece_shapes.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';

import 'test_helpers.dart';

void main() {
  final enabled = previewEnabled('PIECE_PREVIEW');

  testWidgets('render the piece-look preview sheet', (tester) async {
    await tester.runAsync(() async {
      final bytes = await File('assets/images/test_photo.jpg').readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final source = (await codec.getNextFrame()).image;
      addTearDown(source.dispose);
      final pieces = await rasterizePieces(
        source: source,
        columns: 4,
        rows: 3,
        shapes: PieceShapeGrid.generate(columns: 4, rows: 3, seed: 11),
      );
      addTearDown(() {
        for (final piece in pieces) {
          piece.dispose();
        }
      });

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 1240, 760),
        Paint()..color = StudioColors.board,
      );

      // Shadow first, then body — same stacking as the game's layers.
      void drawPiece(ShapedPieceImage piece, Offset at, double targetWidth) {
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

      // One large piece (zoomed-in judgement), two medium (board scale),
      // three small (tray scale).
      drawPiece(pieces[5], const Offset(40, 90), 520);
      drawPiece(pieces[6], const Offset(640, 70), 260);
      drawPiece(pieces[9], const Offset(640, 380), 260);
      drawPiece(pieces[1], const Offset(960, 120), 110);
      drawPiece(pieces[2], const Offset(960, 300), 110);
      drawPiece(pieces[10], const Offset(960, 480), 110);

      final picture = recorder.endRecording();
      final sheet = await picture.toImage(1240, 760);
      picture.dispose();
      addTearDown(sheet.dispose);
      await writePreviewPng(sheet, 'docs/piece-look-preview.png');
    });
  }, skip: !enabled);
}
