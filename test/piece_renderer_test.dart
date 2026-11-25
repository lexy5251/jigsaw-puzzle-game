import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/piece_renderer.dart';
import 'package:jigsaw_puzzle/piece_shapes.dart';
import 'package:jigsaw_puzzle/whimsy_plan.dart';
import 'package:jigsaw_puzzle/whimsy_shapes.dart';

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
      // so every piece image is (20 + 12) x (16 + 12). The shadow bakes at
      // half resolution into that box grown by shadowPad = ceil(1.6 + 3*1.1)
      // = 5 on every side, so blur is never clipped at a tab tip.
      for (final piece in pieces) {
        expect(piece.bleed.x, 6);
        expect(piece.bleed.y, 6);
        expect(piece.sprite.srcSize.x, 32);
        expect(piece.sprite.srcSize.y, 28);
        expect(piece.shadowPad, 5);
        expect(piece.restShadow.srcSize.x, 21);
        expect(piece.restShadow.srcSize.y, 19);
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

  testWidgets('dimensional artwork stays inside the outline; shadow is apart', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final source = await makeSource();
      addTearDown(source.dispose);
      final pieces = await rasterizePieces(
        source: source,
        columns: 1,
        rows: 1,
        shapes: PieceShapeGrid.generate(columns: 1, rows: 1, seed: 3),
      );
      addTearDown(pieces.single.dispose);

      Future<ui.Image> capture(void Function(Canvas) draw) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..scale(3);
        draw(canvas);
        final picture = recorder.endRecording();
        try {
          return await picture.toImage(300, 300);
        } finally {
          picture.dispose();
        }
      }

      const bounds = Rect.fromLTWH(20, 20, 60, 52);
      final artwork = pieces.single.artwork;
      final body = await capture(
        (canvas) => artwork.render(canvas, bounds: bounds),
      );
      final restingShadow = await capture(
        (canvas) => artwork.renderShadow(canvas, bounds: bounds),
      );
      final liftedShadow = await capture(
        (canvas) => artwork.renderShadow(canvas, bounds: bounds, lifted: true),
      );
      addTearDown(body.dispose);
      addTearDown(restingShadow.dispose);
      addTearDown(liftedShadow.dispose);

      final images = {
        for (final entry in {
          'body': body,
          'resting': restingShadow,
          'lifted': liftedShadow,
        }.entries)
          entry.key: (await entry.value.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!,
      };
      int channel(String image, double x, double y, int channel) =>
          images[image]!.getUint8(
            ((y * 3).floor() * 300 + (x * 3).floor()) * 4 + channel,
          );

      // The face spans (30,30)..(70,62). Clean-flat: the photo is untouched
      // from center to cut and the margins stay clear.
      expect(channel('body', 50, 46, 0), 255);
      expect(channel('body', 50, 46, 1), 0);
      expect(channel('body', 50, 46, 3), 255);
      expect(channel('body', 22, 22, 3), 0);
      // The photo runs edge-to-edge (no rim band; the soft warm edge shade
      // only dims and tints it slightly), and not a pixel of body lands
      // outside the outline — joined neighbours sit flush against it.
      expect(channel('body', 50, 61.5, 0), greaterThan(200));
      expect(channel('body', 50, 61.5, 1), lessThan(40));
      expect(channel('body', 50, 63, 3), 0);
      // The shadow is a separate pass (drawn below bodies by the game's
      // layers); it reaches past the outline's lower edge, deeper when
      // lifted.
      expect(channel('resting', 50, 64, 3), greaterThan(0));
      expect(
        channel('lifted', 50, 66, 3),
        greaterThan(channel('resting', 50, 66, 3)),
        reason: 'A lifted piece casts a deeper shadow below its edge.',
      );
    });
  });

  testWidgets('a whimsy plan grows only the flap neighbors, pixels confined', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // 100x80 source, 5x5 grid: cell = 20x16. A heart whimsy at the center
      // cell (index 12) with its four flap neighbors.
      Future<ui.Image> makeWideSource() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 100, 80),
          Paint()..color = const Color(0xFFFF0000),
        );
        final picture = recorder.endRecording();
        try {
          return await picture.toImage(100, 80);
        } finally {
          picture.dispose();
        }
      }

      final source = await makeWideSource();
      addTearDown(source.dispose);
      const plan = WhimsyPlan({12: WhimsyShape.heart});
      final pieces = await rasterizePieces(
        source: source,
        columns: 5,
        rows: 5,
        shapes: PieceShapeGrid.generate(
          columns: 5,
          rows: 5,
          seed: 3,
          whimsyCells: plan.cellIndexes,
        ),
        whimsyPlan: plan,
      );
      addTearDown(() {
        for (final piece in pieces) {
          piece.dispose();
        }
      });

      // Only the four flap neighbors need room to reach the whimsy cell's
      // center: their bleed grows from the knob's 6 to ceil(20 / 2) + 1 =
      // 11. Everything else — the whimsy piece included, its figure never
      // leaves the cell — keeps the knob bleed, so tray thumbnails stay as
      // large as on a whimsy-free board.
      const flapNeighbors = {7, 11, 13, 17};
      for (var index = 0; index < pieces.length; index++) {
        final flap = flapNeighbors.contains(index);
        expect(pieces[index].bleed.x, flap ? 11 : 6, reason: '$index');
        expect(pieces[index].sprite.srcSize.x, flap ? 42 : 32, reason: '$index');
        expect(pieces[index].sprite.srcSize.y, flap ? 38 : 28, reason: '$index');
      }

      Future<int Function(int x, int y)> alphaOf(int index) async {
        final image = pieces[index].sprite.image;
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        return (x, y) => data.getUint8((y * image.width + x) * 4 + 3);
      }

      // The whimsy piece is the figure alone: photo at the cell center,
      // nothing at the cell corner (a normal piece would be opaque there).
      final whimsyAlpha = await alphaOf(12);
      expect(whimsyAlpha(6 + 10, 6 + 8), 255);
      expect(whimsyAlpha(6, 6), 0);
      expect(whimsyAlpha(6 + 1, 6 + 1), 0);

      // The neighbor above (index 7) grows a flap into the whimsy cell's
      // top triangle: opaque deep inside the triangle, above the figure and
      // clear of the antialiased diagonal seams...
      final aboveAlpha = await alphaOf(7);
      expect(aboveAlpha(11 + 10, 11 + 16 + 1), 255);
      // ...its own cell face is untouched...
      expect(aboveAlpha(11 + 10, 11 + 8), 255);
      // ...and it claims nothing outside its triangle (left seam region of
      // the whimsy cell belongs to the left neighbor).
      expect(aboveAlpha(11 + 1, 11 + 16 + 6), 0);

      // A piece far from the whimsy keeps its plain knob outline: opaque at
      // its cell center... it is cut identically to a plain grid.
      final farAlpha = await alphaOf(0);
      expect(farAlpha(6 + 10, 6 + 8), 255);
    });
  });

  testWidgets('a plan without matching grid whimsy cells trips the assert', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final source = await makeSource();
      addTearDown(source.dispose);
      // A grid cut without whimsyCells would keep knobs on the edges facing
      // the figure — a silent hole in the picture. The renderer refuses the
      // mismatched pair up front.
      await expectLater(
        rasterizePieces(
          source: source,
          columns: 2,
          rows: 2,
          shapes: PieceShapeGrid.generate(columns: 2, rows: 2, seed: 3),
          whimsyPlan: const WhimsyPlan({0: WhimsyShape.heart}),
        ),
        throwsAssertionError,
      );
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
            // Each piece bakes two images: the decorated body and its
            // half-resolution contact shadow.
            if (fail) {
              await expectLater(rendering, throwsStateError);
              expect(images.length, 6);
              expect(images.every((image) => image.debugDisposed), isTrue);
            } else {
              final pieces = await rendering;
              expect(images.length, 8);
              expect(images.every((image) => !image.debugDisposed), isTrue);
              for (final piece in pieces) {
                piece.dispose();
              }
            }
            expect(pictures.length, fail ? 6 : 8);
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
