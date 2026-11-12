// Tray previews render live from the full-resolution photo (phone issue
// #14: "pieces on the bottom look so cheap" at 216 pieces). The baked
// sprite holds only a piece's small crop of the photo, and the tray shows
// every piece at the same screen size — on dense grids a sprite blit
// upscales past the source resolution and blurs. These tests pin the live
// path by comparing the tray's actual pixels (captured at 3x, like a 3x-DPR
// phone) against a composite built from PieceArtwork.render directly.

import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/piece_tray.dart';
import 'package:jigsaw_puzzle/puzzle_piece.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';

import 'test_helpers.dart';

void main() {
  PieceTray trayOf(JigsawGame game) =>
      game.camera.viewport.children.whereType<PieceTray>().single;

  Future<JigsawGame> bootFresh(
    WidgetTester tester, {
    required int columns,
    required int rows,
  }) async {
    final game = JigsawGame(
      imageAsset: 'test_photo.jpg',
      columns: columns,
      rows: rows,
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(GameWidget(game: game));
      await game.loaded;
    });
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return game;
  }

  /// Renders the tray subtree at 3x into an image, in tray-local space.
  Future<ui.Image> captureTray(PieceTray tray) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(3)
      ..translate(-tray.position.x, -tray.position.y);
    tray.renderTree(canvas);
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(
        (tray.size.x * 3).ceil(),
        (tray.size.y * 3).ceil(),
      );
    } finally {
      picture.dispose();
    }
  }

  /// Rebuilds the expected tray pixels from PieceArtwork.render directly:
  /// background, clipped strip of previews (the landing piece stays blank),
  /// then the landing flyer above the clip — mirroring the tray's layering.
  Future<ui.Image> compositeTray(PieceTray tray) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(3);
    final trayRect = Rect.fromLTWH(0, 0, tray.size.x, tray.size.y);
    canvas.drawRect(trayRect, Paint()..color = StudioColors.tray);

    final photoPaint = Paint()
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = true;
    canvas.save();
    canvas.clipRect(trayRect);
    final indexes = tray.visiblePieceIndexes;
    final positions = tray.thumbnailPositions;
    final thumbnailSize = tray.thumbnailSize;
    for (var i = 0; i < indexes.length; i++) {
      // The flyer draws the landing piece; its slot stays blank meanwhile.
      if (indexes[i] == tray.landingPieceIndex) {
        continue;
      }
      // Offscreen columns need no culling here: the clip removes them, so
      // the pixels match the tray's culled render either way.
      final artwork = tray.artworkFor(indexes[i])!;
      final bounds = Rect.fromLTWH(
        positions[i].x - tray.scrollOffset,
        positions[i].y,
        thumbnailSize.x,
        thumbnailSize.y,
      );
      // Thumbnails draw their contact shadow first, like board pieces —
      // the shadow box overhangs the sprite box by the (scaled) pad.
      final pad = tray.restShadowPadFor(indexes[i])!;
      final srcSize = tray.spriteSrcSizeFor(indexes[i])!;
      final padX = pad * bounds.width / srcSize.x;
      final padY = pad * bounds.height / srcSize.y;
      tray.restShadowFor(indexes[i])!.render(
        canvas,
        position: Vector2(bounds.left - padX, bounds.top - padY),
        size: Vector2(bounds.width + 2 * padX, bounds.height + 2 * padY),
        overridePaint: photoPaint,
      );
      artwork.render(
        canvas,
        bounds: bounds,
        decorationScale: artwork.bakedDecorationScale(bounds),
        photoPaint: photoPaint,
      );
    }
    canvas.restore();

    final flightBox = tray.activeFlightBox;
    final flightTarget = tray.activeFlightTarget;
    final landingIndex = tray.landingPieceIndex;
    if (flightBox != null && flightTarget != null && landingIndex != null) {
      final artwork = tray.artworkFor(landingIndex)!;
      final pad = tray.restShadowPadFor(landingIndex)!;
      final srcSize = tray.spriteSrcSizeFor(landingIndex)!;
      final padX = pad * flightBox.width / srcSize.x;
      final padY = pad * flightBox.height / srcSize.y;
      tray.restShadowFor(landingIndex)!.render(
        canvas,
        position: Vector2(flightBox.left - padX, flightBox.top - padY),
        size: Vector2(flightBox.width + 2 * padX, flightBox.height + 2 * padY),
        overridePaint: photoPaint,
      );
      artwork.render(
        canvas,
        bounds: flightBox,
        // The real flyer sizes its edge for the destination slot.
        decorationScale: artwork.bakedDecorationScale(flightTarget),
        photoPaint: photoPaint,
      );
    }

    final picture = recorder.endRecording();
    try {
      return await picture.toImage(
        (tray.size.x * 3).ceil(),
        (tray.size.y * 3).ceil(),
      );
    } finally {
      picture.dispose();
    }
  }

  Future<int> countMismatchedBytes(ui.Image actual, ui.Image expected) async {
    expect(actual.width, expected.width);
    expect(actual.height, expected.height);
    final actualBytes = (await actual.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final expectedBytes = (await expected.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    var mismatches = 0;
    for (var i = 0; i < actualBytes.lengthInBytes; i++) {
      if ((actualBytes.getUint8(i) - expectedBytes.getUint8(i)).abs() > 2) {
        mismatches++;
      }
    }
    return mismatches;
  }

  testWidgets('dense-grid tray previews render live from the photo', (
    tester,
  ) async {
    final game = await bootFresh(tester, columns: 18, rows: 12);
    final tray = trayOf(game);

    await tester.runAsync(() async {
      final actual = await captureTray(tray);
      final expected = await compositeTray(tray);
      addTearDown(actual.dispose);
      addTearDown(expected.dispose);
      // A baked-sprite blit would upscale ~2.7x here and differ everywhere;
      // the live path reproduces the artwork composite exactly.
      expect(await countMismatchedBytes(actual, expected), 0);
    });
  });

  /// Boots a 6x4 game with piece 8 loose on the board and starts its
  /// return flight by dropping it over the tray.
  Future<JigsawGame> bootWithFlightStarted(WidgetTester tester) async {
    const key = 'tray-resolution-flight';
    const width = 1600 / 6;
    const height = 1067 / 4;
    final store = InMemorySaveStore();
    await store.save(
      key,
      PuzzleSaveState(
        trayPieceIndexes: [
          for (var i = 0; i < 24; i++)
            if (i != 8) i,
        ],
        lockedPieceIndexes: const [],
        loosePiecePositions: {8: Vector2(8 % 6 * width, 8 ~/ 6 * height)},
        boardWidth: testPhotoWidth,
      ),
    );
    final game = JigsawGame(
      imageAsset: 'test_photo.jpg',
      columns: 6,
      rows: 4,
      saveStore: store,
      saveKey: key,
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(GameWidget(game: game));
      await game.loaded;
    });
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final piece = game.world.children.whereType<PuzzlePiece>().single;
    final onTray = Vector2(game.size.x / 2, game.size.y - 20);
    game.movePieceTo(piece, game.camera.globalToLocal(onTray) - piece.size / 2);
    piece.settle();
    await tester.pump(const Duration(milliseconds: 16));
    return game;
  }

  testWidgets('the landing flight renders the artwork mid-flight', (
    tester,
  ) async {
    final game = await bootWithFlightStarted(tester);
    final tray = trayOf(game);
    expect(tray.landingPieceIndex, 8);
    expect(tray.activeFlightBox, isNotNull);

    await tester.runAsync(() async {
      final actual = await captureTray(tray);
      final expected = await compositeTray(tray);
      addTearDown(actual.dispose);
      addTearDown(expected.dispose);
      expect(await countMismatchedBytes(actual, expected), 0);
    });

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tray.landingPieceIndex, isNull);
  });

  testWidgets('a flight finished during update draws nothing in its final '
      'mounted frame', (tester) async {
    final game = await bootWithFlightStarted(tester);
    final tray = trayOf(game);
    expect(tray.landingPieceIndex, 8);

    // Pump until the flight finishes inside an update. Flame processes the
    // queued removal only at the START of the next frame's update, so right
    // after the pump that cleared the landing state, the finished flyer is
    // still mounted — the one frame where it must draw nothing while the
    // revealed thumbnail draws.
    var guard = 0;
    while (tray.landingPieceIndex != null && guard < 20) {
      await tester.pump(const Duration(milliseconds: 50));
      guard++;
    }
    expect(tray.landingPieceIndex, isNull);
    expect(tray.activeFlightBox, isNull);

    await tester.runAsync(() async {
      final actual = await captureTray(tray);
      final expected = await compositeTray(tray);
      addTearDown(actual.dispose);
      addTearDown(expected.dispose);
      // The composite has no flyer; a flyer that still painted here would
      // double the rim strokes over the revealed thumbnail.
      expect(await countMismatchedBytes(actual, expected), 0);
    });
  });
}
