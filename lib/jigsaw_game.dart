// Game logic overview:
// 1. onLoad loads the photo and creates columns x rows pieces. It restores
//    saved progress when available; otherwise all pieces start in the tray.
// 2. The camera controls which part of the board is visible and its zoom.
//    The tray stays fixed on screen while the board view moves or zooms.
// 3. onGameResize adjusts the tray and fits the board above it again.
// 4. Dragging empty space pans the camera; pinching or scrolling zooms
//    around the fingers or cursor. Camera movement and zoom are limited.
// 5. keepPieceClearOfTray moves dropped pieces up if they overlap the tray.
// 6. onPieceLocked counts placed pieces and shows "Puzzle complete!"
//    when every piece is locked in its correct position.
// 7. persistProgress saves the board and tray after a move, or deletes the
//    save when the puzzle is complete.
//
// PieceTray and PuzzlePiece handle dragging pieces and snapping them into place.

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'piece_tray.dart';
import 'puzzle_logic.dart';
import 'puzzle_piece.dart';
import 'puzzle_save.dart';

/// The board uses image pixels as world units; the tray stays in screen space.
/// Gestures on empty space pan and zoom the camera.
class JigsawGame extends FlameGame
    with DragCallbacks, ScaleCallbacks, ScrollCallbacks {
  JigsawGame({
    required this.imageAsset,
    required this.columns,
    required this.rows,
    this.saveStore,
    this.saveKey,
  });

  /// Image file name under assets/images/ (Flame's default image prefix).
  final String imageAsset;
  final int columns;
  final int rows;

  /// Reads and writes saved progress. Tests can omit storage to play in memory.
  final PuzzleSaveStore? saveStore;

  /// Identifies this image and grid size in storage.
  /// Saving and loading require both [saveStore] and [saveKey].
  final String? saveKey;

  /// Live count of correctly placed pieces, used to detect completion.
  late final PuzzleProgress progress;

  // Live piece state: the tray holds unused pieces; world holds board pieces.
  PieceTray? _tray;
  late Vector2 _boardSize;

  late double _fitZoom;
  double _zoomAtPinchStart = 1;

  double get _trayHeight => min(size.y * 0.18, 130);

  @override
  Color backgroundColor() => const Color(0xFF2E3440);

  @override
  Future<void> onLoad() async {
    final image = await images.load(imageAsset);

    final pieceSize = Vector2(image.width / columns, image.height / rows);
    _boardSize = Vector2(image.width.toDouble(), image.height.toDouble());
    progress = PuzzleProgress(totalPieces: columns * rows);

    _addBoardOutline();
    final allPieces = _createPieceData(image, pieceSize);
    final savedState = await _loadSavedProgress(allPieces.length);

    final List<PieceData> trayPieces;
    if (savedState == null) {
      // Start fresh: every piece goes into the tray in a random order.
      trayPieces = List.of(allPieces)..shuffle();
    } else {
      // Resume: restore the board and preserve the remaining tray order.
      _restoreBoardPieces(savedState, allPieces, pieceSize);
      trayPieces = [
        for (final index in savedState.trayPieceIndexes) allPieces[index],
      ];
    }

    _addTray(trayPieces, pieceSize);
    _fitCameraToBoard();
  }

  void _addBoardOutline() {
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
  }

  /// Cuts the image into pieces with stable indexes for saving and restoring.
  List<PieceData> _createPieceData(ui.Image image, Vector2 pieceSize) {
    final pieces = <PieceData>[];
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final correctPosition = Vector2(
          column * pieceSize.x,
          row * pieceSize.y,
        );
        pieces.add(
          PieceData(
            index: row * columns + column,
            sprite: Sprite(
              image,
              srcPosition: correctPosition.clone(),
              srcSize: pieceSize,
            ),
            correctPosition: correctPosition,
          ),
        );
      }
    }
    return pieces;
  }

  void _addTray(List<PieceData> pieces, Vector2 pieceSize) {
    final tray = PieceTray(
      pieces: pieces,
      pieceWorldSize: pieceSize,
      position: Vector2(0, size.y - _trayHeight),
      size: Vector2(size.x, _trayHeight),
    );
    _tray = tray;
    camera.viewport.add(tray);
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
    persistProgress();
  }

  /// Piece indexes still in the tray — exposed for tests.
  @visibleForTesting
  List<int> get trayPieceIndexes => _tray?.remainingPieceIndexes ?? const [];

  /// Returns a usable save, or null to start fresh.
  /// Storage may be disabled, or the save may be missing or invalid.
  Future<PuzzleSaveState?> _loadSavedProgress(int totalPieces) async {
    final store = saveStore;
    final key = saveKey;
    if (store == null || key == null) {
      return null;
    }
    final state = await store.load(key);
    if (state == null || !state.isConsistentFor(totalPieces)) {
      return null;
    }
    return state;
  }

  /// Recreates saved board pieces: locked ones in place, loose ones where
  /// they were dropped. Tray pieces are handled by the tray itself.
  void _restoreBoardPieces(
    PuzzleSaveState state,
    List<PieceData> allPieces,
    Vector2 pieceSize,
  ) {
    PuzzlePiece createPiece(PieceData data, Vector2 position) => PuzzlePiece(
      index: data.index,
      sprite: data.sprite,
      size: pieceSize.clone(),
      position: position,
      correctPosition: data.correctPosition.clone(),
    );

    for (final index in state.lockedPieceIndexes) {
      final data = allPieces[index];
      progress.lockPiece();
      world.add(
        createPiece(data, data.correctPosition.clone())..restoreAsLocked(),
      );
    }
    for (final entry in state.loosePiecePositions.entries) {
      world.add(createPiece(allPieces[entry.key], entry.value.clone()));
    }
  }

  /// Writes the current progress; removes the save once the puzzle is done.
  /// Fire-and-forget: gameplay never waits on storage.
  void persistProgress() {
    final store = saveStore;
    final key = saveKey;
    if (store == null || key == null) {
      return;
    }
    if (progress.isComplete) {
      store.delete(key);
      return;
    }

    store.save(key, _createSaveState());
  }

  /// Copies the live board and tray state into a snapshot for storage.
  PuzzleSaveState _createSaveState() {
    final lockedPieceIndexes = <int>[];
    final loosePiecePositions = <int, Vector2>{};
    for (final piece in world.children.whereType<PuzzlePiece>()) {
      if (piece.isLocked) {
        lockedPieceIndexes.add(piece.index);
      } else {
        loosePiecePositions[piece.index] = piece.position.clone();
      }
    }
    return PuzzleSaveState(
      trayPieceIndexes: _tray?.remainingPieceIndexes ?? const [],
      lockedPieceIndexes: lockedPieceIndexes,
      loosePiecePositions: loosePiecePositions,
    );
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
