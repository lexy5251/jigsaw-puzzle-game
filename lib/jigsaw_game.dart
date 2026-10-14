// Game logic overview:
// 1. onLoad loads the photo, creates 24 pieces in a 6 x 4 grid, shuffles
//    them into the bottom tray, and draws the board outline.
// 2. The camera controls which part of the board is visible and its zoom.
//    The tray stays fixed on screen while the board view moves or zooms.
// 3. onGameResize adjusts the tray and fits the board above it again.
// 4. Dragging empty space pans the camera; pinching or scrolling zooms
//    around the fingers or cursor. Camera movement and zoom are limited.
// 5. keepPieceClearOfTray moves dropped pieces up if they overlap the tray.
// 6. onPieceLocked counts placed pieces and shows "Puzzle complete!"
//    when every piece is locked in its correct position.
//
// PieceTray and PuzzlePiece handle dragging pieces and snapping them into place.

import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'piece_tray.dart';
import 'puzzle_logic.dart';
import 'puzzle_piece.dart';

const _columns = 6;
const _rows = 4;

/// The board uses image pixels as world units; the tray stays in screen space.
/// Gestures on empty space pan and zoom the camera.
class JigsawGame extends FlameGame
    with DragCallbacks, ScaleCallbacks, ScrollCallbacks {
  late final PuzzleProgress progress;

  PieceTray? _tray;
  late Vector2 _boardSize;

  late double _fitZoom;
  double _zoomAtPinchStart = 1;

  double get _trayHeight => min(size.y * 0.18, 130);

  @override
  Color backgroundColor() => const Color(0xFF2E3440);

  @override
  Future<void> onLoad() async {
    final image = await images.load('test_photo.jpg');

    final pieceSize = Vector2(image.width / _columns, image.height / _rows);
    _boardSize = Vector2(image.width.toDouble(), image.height.toDouble());
    progress = PuzzleProgress(totalPieces: _columns * _rows);

    world.add(
      RectangleComponent(
        size: _boardSize.clone(),
        priority: -2, // Render below locked pieces.
        paint: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0x66FFFFFF),
      ),
    );

    final pieces = <PieceData>[
      for (var row = 0; row < _rows; row++)
        for (var column = 0; column < _columns; column++)
          PieceData(
            sprite: Sprite(
              image,
              srcPosition: Vector2(column * pieceSize.x, row * pieceSize.y),
              srcSize: pieceSize,
            ),
            correctPosition: Vector2(column * pieceSize.x, row * pieceSize.y),
          ),
    ]..shuffle();

    final tray = PieceTray(
      pieces: pieces,
      pieceWorldSize: pieceSize,
      position: Vector2(0, size.y - _trayHeight),
      size: Vector2(size.x, _trayHeight),
    );
    _tray = tray;
    camera.viewport.add(tray);

    _fitCameraToBoard();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);

    final tray = _tray;
    if (tray == null) {
      return; // onLoad sets up the layout after loading finishes.
    }

    tray.resizeTo(
      position: Vector2(0, size.y - _trayHeight),
      size: Vector2(size.x, _trayHeight),
    );
    _fitCameraToBoard();
  }

  void _fitCameraToBoard() {
    final availableBoardSize = Vector2(size.x, size.y - _trayHeight);
    _fitZoom = min(
      availableBoardSize.x * 0.92 / _boardSize.x,
      availableBoardSize.y * 0.85 / _boardSize.y,
    );

    // Offset the camera so the board is centered in the space above the tray.
    final trayOffset = Vector2(0, _trayHeight / (2 * _fitZoom));
    camera.viewfinder
      ..anchor = Anchor.center
      ..zoom = _fitZoom
      ..position = _boardSize / 2 + trayOffset;
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (isScaling) {
      return;
    }

    final dragDelta = event.canvasEndPosition - event.canvasStartPosition;
    camera.viewfinder.position -= dragDelta / camera.viewfinder.zoom;
    _clampCamera();
  }

  @override
  void onScaleStart(ScaleStartEvent event) {
    super.onScaleStart(event);
    _zoomAtPinchStart = camera.viewfinder.zoom;
  }

  @override
  void onScaleUpdate(ScaleUpdateEvent event) {
    camera.viewfinder.position -=
        event.focalPointDelta / camera.viewfinder.zoom;

    // event.scale is cumulative since the gesture started.
    _zoomAroundCanvasPoint(
      clampZoom(_zoomAtPinchStart * event.scale, _fitZoom),
      event.canvasEndPosition,
    );
  }

  @override
  void onScroll(ScrollEvent event) {
    const scrollPixelsPerZoomDoubling = 300;
    final zoomFactor = pow(
      2,
      -event.scrollDelta.y / scrollPixelsPerZoomDoubling,
    ).toDouble();
    _zoomAroundCanvasPoint(
      clampZoom(camera.viewfinder.zoom * zoomFactor, _fitZoom),
      event.canvasPosition,
    );
  }

  /// Keeps the world point under [canvasPoint] fixed on screen while zooming.
  void _zoomAroundCanvasPoint(double newZoom, Vector2 canvasPoint) {
    final worldPointBeforeZoom = camera.globalToLocal(canvasPoint);
    camera.viewfinder.zoom = newZoom;
    final worldPointAfterZoom = camera.globalToLocal(canvasPoint);
    camera.viewfinder.position += worldPointBeforeZoom - worldPointAfterZoom;
    _clampCamera();
  }

  void _clampCamera() {
    final margin = _boardSize / 2;
    final cameraPosition = camera.viewfinder.position;
    camera.viewfinder.position = Vector2(
      cameraPosition.x.clamp(-margin.x, _boardSize.x + margin.x).toDouble(),
      cameraPosition.y.clamp(-margin.y, _boardSize.y + margin.y).toDouble(),
    );
  }

  void keepPieceClearOfTray(PuzzlePiece piece) {
    const gap = 8.0;
    final pieceBottomOnScreen = camera
        .localToGlobal(piece.position + Vector2(0, piece.size.y))
        .y;
    final maxPieceBottomOnScreen = size.y - _trayHeight - gap;
    final overlap = pieceBottomOnScreen - maxPieceBottomOnScreen;

    if (overlap > 0) {
      piece.position.y -= overlap / camera.viewfinder.zoom;
    }
  }

  void onPieceLocked() {
    if (progress.lockPiece()) {
      _showCompletionText();
    }
  }

  void _showCompletionText() {
    camera.viewport.add(
      TextComponent(
        text: 'Puzzle complete!',
        anchor: Anchor.center,
        position: size / 2,
        priority: 200,
        textRenderer: TextPaint(
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
