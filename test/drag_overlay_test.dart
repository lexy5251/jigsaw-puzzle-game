import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/piece_tray.dart';
import 'package:jigsaw_puzzle/puzzle_piece.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';

/// A piece carried across the tray must stay visible (2026-11-06 phone
/// request): the tray overlay re-renders exactly the elevated pieces.
void main() {
  Future<JigsawGame> bootGame(WidgetTester tester) async {
    final game = JigsawGame(imageAsset: 'test_photo.jpg', columns: 6, rows: 4);
    await tester.runAsync(() async {
      await tester.pumpWidget(GameWidget(game: game));
      await game.loaded;
    });
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return game;
  }

  testWidgets('a piece is elevated while dragged and grounded after', (
    tester,
  ) async {
    final game = await bootGame(tester);

    // Lift the first thumbnail out of the tray and hold it over the tray.
    const trayThumbTouch = Offset(50, 460);
    final gesture = await tester.startGesture(trayThumbTouch);
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(trayThumbTouch + Offset(0, -60.0 * i / 8));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final piece = game.world.children.whereType<PuzzlePiece>().single;
    expect(piece.isElevated, isTrue);
    expect(game.elevatedPieces, contains(piece));

    // Back over the tray: the overlay renders it there; frames must not
    // throw while it draws through the camera transform.
    await gesture.moveTo(const Offset(200, 500));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);

    await gesture.up();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Released over the tray -> returned to it; nothing stays elevated.
    expect(game.elevatedPieces, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final zoom in [1.0, 2.0]) {
    testWidgets('overlay only changes tray pixels at zoom $zoom', (
      tester,
    ) async {
      final store = InMemorySaveStore();
      const key = 'overlay-test';
      await store.save(
        key,
        PuzzleSaveState(
          trayPieceIndexes: [for (var i = 1; i < 24; i++) i],
          lockedPieceIndexes: const [],
          loosePiecePositions: {0: Vector2(300, 220)},
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
      game.camera.viewfinder.zoom = zoom;
      final piece = game.world.children.whereType<PuzzlePiece>().single;
      final tray = game.camera.viewport.children.whereType<PieceTray>().single;
      game.movePieceTo(
        piece,
        game.camera.globalToLocal(Vector2(300, tray.y - 40)),
      );
      await tester.pump(const Duration(milliseconds: 16));

      Future<ui.Image> render() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(game.backgroundColor(), BlendMode.src);
        game.render(canvas);
        final picture = recorder.endRecording();
        try {
          return await picture.toImage(800, 600);
        } finally {
          picture.dispose();
        }
      }

      // Three frames: resting, dragged without the overlay, dragged with it.
      final resting = (await tester.runAsync(render))!;
      addTearDown(resting.dispose);
      game.beginPieceDrag(piece);
      final overlay = game.elevatedPieceOverlay;
      overlay.removeFromParent();
      await tester.pump(const Duration(milliseconds: 16));
      final dragged = (await tester.runAsync(render))!;
      addTearDown(dragged.dispose);
      game.camera.viewport.add(overlay);
      await tester.pump(const Duration(milliseconds: 16));
      final overlaid = (await tester.runAsync(render))!;
      addTearDown(overlaid.dispose);

      // Pickup may repaint only the piece's own screen area (the live body
      // and its deepened shadow), inflated a little for the shadow's blur.
      final topLeft = game.camera.localToGlobal(piece.position);
      final pieceRect = Rect.fromLTWH(
        topLeft.x - piece.renderBleed.x * zoom,
        topLeft.y - piece.renderBleed.y * zoom,
        piece.sprite!.srcSize.x * zoom,
        piece.sprite!.srcSize.y * zoom,
      ).inflate(12);

      await tester.runAsync(() async {
        final rest = (await resting.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final drag = (await dragged.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final over = (await overlaid.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        var aboveChanged = 0;
        var trayChanged = 0;
        var strayPickupChanged = 0;
        var pieceChanged = 0;
        for (var y = 0; y < 600; y++) {
          for (var x = 0; x < 800; x++) {
            final index = (y * 800 + x) * 4;
            if (drag.getUint32(index) != over.getUint32(index)) {
              if (y < tray.y.floor()) {
                aboveChanged++;
              } else {
                trayChanged++;
              }
            }
            if (y < tray.y.floor() &&
                rest.getUint32(index) != over.getUint32(index)) {
              if (pieceRect.contains(Offset(x.toDouble(), y.toDouble()))) {
                pieceChanged++;
              } else {
                strayPickupChanged++;
              }
            }
          }
        }
        expect(
          aboveChanged,
          0,
          reason: 'Visible board edges must not be painted twice.',
        );
        expect(
          trayChanged,
          greaterThan(0),
          reason: 'The carried piece must appear above the tray.',
        );
        expect(
          strayPickupChanged,
          0,
          reason: 'Pickup must not repaint anything beyond the piece itself.',
        );
        expect(
          pieceChanged,
          greaterThan(0),
          reason: 'Pickup must visibly lift the piece (deeper shadow).',
        );
      });
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
