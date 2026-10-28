import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/piece_renderer.dart';
import 'package:jigsaw_puzzle/piece_shapes.dart';

class _FailingShapeGrid extends PieceShapeGrid {
  _FailingShapeGrid() : super.generate(columns: 2, rows: 2, seed: 3);

  @override
  PieceShape shapeAtIndex(int index) {
    if (index == 1) throw StateError('A cut failed');
    return super.shapeAtIndex(index);
  }
}

void main() {
  /// A solid red 40x32 photo stand-in.
  Future<ui.Image> makeSource() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 40, 32),
      Paint()..color = const Color(0xFFFF0000),
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(40, 32);
    } finally {
      picture.dispose();
    }
  }

  testWidgets('cuts shaped piece images with a uniform bleed margin', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final source = await makeSource();
      addTearDown(source.dispose);
      final pieces = await rasterizePieces(
        source: source,
        columns: 2,
        rows: 2,
        shapes: PieceShapeGrid.generate(columns: 2, rows: 2, seed: 3),
      );
      addTearDown(() {
        for (final piece in pieces) {
          piece.dispose();
        }
      });

      expect(pieces.length, 4);

      // Cell = 20x16, shorter side 16: bleed = ceil(0.275 * 16) + 1 = 6,
      // so every piece image is (20 + 12) x (16 + 12).
      for (final piece in pieces) {
        expect(piece.bleed.x, 6);
        expect(piece.bleed.y, 6);
        expect(piece.sprite.srcSize.x, 32);
        expect(piece.sprite.srcSize.y, 28);
      }
    });
  });

  testWidgets('piece images are transparent outside the shape, photo inside', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final source = await makeSource();
      addTearDown(source.dispose);
      final pieces = await rasterizePieces(
        source: source,
        columns: 2,
        rows: 2,
        shapes: PieceShapeGrid.generate(columns: 2, rows: 2, seed: 3),
      );
      addTearDown(() {
        for (final piece in pieces) {
          piece.dispose();
        }
      });

      final image = pieces.first.sprite.image;
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      int alphaAt(int x, int y) => data.getUint8((y * image.width + x) * 4 + 3);
      int redAt(int x, int y) => data.getUint8((y * image.width + x) * 4);

      // Image corner lies in the bleed margin, outside any knob.
      expect(alphaAt(0, 0), 0);
      // The cell's center always belongs to the piece and shows the photo.
      expect(alphaAt(16, 14), 255);
      expect(redAt(16, 14), greaterThan(200));
    });
  });

  for (final fail in [false, true]) {
    testWidgets(
      'releases rendering resources after ${fail ? 'failure' : 'success'}',
      (tester) async {
        await tester.runAsync(() async {
          final source = await makeSource();
          final pictures = <ui.Picture>[];
          final images = <ui.Image>[];
          final previousPictureHook = ui.Picture.onCreate;
          final previousImageHook = ui.Image.onCreate;
          ui.Picture.onCreate = (picture) {
            previousPictureHook?.call(picture);
            pictures.add(picture);
          };
          ui.Image.onCreate = (image) {
            previousImageHook?.call(image);
            images.add(image);
          };
          try {
            final rendering = rasterizePieces(
              source: source,
              columns: 2,
              rows: 2,
              shapes: fail
                  ? _FailingShapeGrid()
                  : PieceShapeGrid.generate(columns: 2, rows: 2, seed: 3),
            );
            if (fail) {
              await expectLater(rendering, throwsStateError);
              expect(images.length, 3);
              expect(images.every((image) => image.debugDisposed), isTrue);
            } else {
              final pieces = await rendering;
              expect(images.length, 4);
              expect(images.every((image) => !image.debugDisposed), isTrue);
              for (final piece in pieces) {
                piece.dispose();
              }
            }
            expect(pictures.length, fail ? 3 : 4);
            expect(pictures.every((picture) => picture.debugDisposed), isTrue);
            expect(source.debugDisposed, isFalse);
          } finally {
            ui.Picture.onCreate = previousPictureHook;
            ui.Image.onCreate = previousImageHook;
            for (final image in images.where((image) => !image.debugDisposed)) {
              image.dispose();
            }
            source.dispose();
          }
        });
      },
    );
  }
}
