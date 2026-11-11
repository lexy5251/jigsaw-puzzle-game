// Dev tool, not a test: renders every candidate board background from
// boardColorOptions to docs/board-color-preview.png so the colors can be
// judged as an image before a device build. Each panel shows the piece
// cases that motivated the feature: snowy (white-heavy) pieces plus a
// colorful control piece, the board outline in that color's paired stroke,
// and the tray wood. Skipped unless BOARD_COLOR_PREVIEW=1:
//   BOARD_COLOR_PREVIEW=1 flutter test test/board_color_preview_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/piece_renderer.dart';
import 'package:jigsaw_puzzle/piece_shapes.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';

const _panelWidth = 620.0;
const _panelHeight = 440.0;
const _columns = 3;

void main() {
  final enabled = Platform.environment['BOARD_COLOR_PREVIEW'] == '1';

  testWidgets('render the board-color preview sheet', (tester) async {
    await tester.runAsync(() async {
      // Real font so the hex captions are readable (tests default to Ahem).
      final fontLoader = FontLoader('Nunito')
        ..addFont(
          File(
            'assets/fonts/Nunito-Bold.ttf',
          ).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
        );
      await fontLoader.load();

      Future<List<ShapedPieceImage>> cutPieces(String path, int seed) async {
        final bytes = await File(path).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final source = (await codec.getNextFrame()).image;
        addTearDown(source.dispose);
        final pieces = await rasterizePieces(
          source: source,
          columns: 4,
          rows: 3,
          shapes: PieceShapeGrid.generate(columns: 4, rows: 3, seed: seed),
        );
        addTearDown(() {
          for (final piece in pieces) {
            piece.dispose();
          }
        });
        return pieces;
      }

      // The motivating case: a white-heavy snow photo, hard to see on the
      // current tan. test_photo is the colorful control.
      final snowPieces = await cutPieces(
        'assets/images/landscapes/snowcapped_lake.jpg',
        7,
      );
      final controlPieces = await cutPieces('assets/images/test_photo.jpg', 11);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

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

      String hexOf(Color color) =>
          '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';

      for (final (index, option) in boardColorOptions.indexed) {
        final origin = Offset(
          (index % _columns) * _panelWidth,
          (index ~/ _columns) * _panelHeight,
        );
        canvas.save();
        canvas.translate(origin.dx, origin.dy);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, _panelWidth, _panelHeight),
          Paint()..color = option.background,
        );

        // Board outline exactly as the game strokes it (2px).
        canvas.drawRect(
          const Rect.fromLTWH(40, 64, 350, 240),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = option.outline,
        );

        // Two snow pieces on the "board", the control piece beside it,
        // and a small snow piece resting on the tray wood.
        drawPiece(snowPieces[1], const Offset(70, 95), 150);
        drawPiece(snowPieces[6], const Offset(230, 160), 150);
        drawPiece(controlPieces[5], const Offset(430, 110), 150);
        canvas.drawRect(
          const Rect.fromLTWH(0, _panelHeight - 86, _panelWidth, 86),
          Paint()..color = StudioColors.tray,
        );
        drawPiece(snowPieces[2], const Offset(48, _panelHeight - 74), 72);
        drawPiece(controlPieces[9], const Offset(150, _panelHeight - 74), 72);

        final darkFill = option.background.computeLuminance() < 0.35;
        final caption = TextPainter(
          text: TextSpan(
            text: '${option.label}  ${hexOf(option.background)}',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w700,
              fontSize: 24,
              color: darkFill ? StudioColors.onTerracotta : StudioColors.ink,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        caption.paint(canvas, const Offset(24, 18));
        canvas.restore();
      }

      const sheetWidth = _panelWidth * _columns;
      const sheetHeight =
          _panelHeight * 2; // 6 options → 2 rows; grows if more are added.
      final picture = recorder.endRecording();
      final sheet = await picture.toImage(
        sheetWidth.toInt(),
        sheetHeight.toInt(),
      );
      picture.dispose();
      addTearDown(sheet.dispose);
      final png = await sheet.toByteData(format: ui.ImageByteFormat.png);
      final out = File('docs/board-color-preview.png');
      await out.writeAsBytes(png!.buffer.asUint8List());
      debugPrint('board-color preview written to ${out.absolute.path}');
    });
  }, skip: !enabled);
}
