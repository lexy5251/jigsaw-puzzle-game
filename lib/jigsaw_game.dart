// Game logic overview:
// 1. onLoad loads the photo and creates columns x rows pieces. It restores
//    saved progress when available; otherwise all pieces start in the tray.
// 2. The camera controls which part of the board is visible and its zoom.
//    The tray stays fixed on screen while the board view moves or zooms.
// 3. onGameResize adjusts the tray and fits the board above it again.
// 4. Dragging empty space pans the camera; pinching or scrolling zooms
//    around the fingers or cursor. Camera movement and zoom are limited.
// 5. keepPieceClearOfTray moves dropped pieces up if they overlap the tray.
// 6. onPieceLocked counts placed pieces. When the last one locks, a glow
//    washes over the finished image and onCompleted tells the host screen
//    (which records the completion and shows the celebration UI).
// 7. persistProgress saves the board and tray once a fresh puzzle has loaded
//    and after every move. Progress is deleted only after the host confirms
//    that the completion record was saved successfully — and only while this
//    game still owns the save key: reopening the same puzzle hands ownership
//    to the new session, so a lingering old session cannot touch its save.
//
// PieceTray and PuzzlePiece handle dragging pieces and snapping them into place.

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game_sounds.dart';
import 'piece_renderer.dart';
import 'piece_shapes.dart';
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
    this.sounds,
    this.onCompleted,
    this.onBoardLoaded,
  });

  /// Owned by this game and disposed with it; null keeps the game silent.
  final GameSounds? sounds;

  /// Reports whether this game resumed from a save (true) or started fresh,
  /// once loading finishes. The host screen exposes it via Semantics so
  /// end-to-end tests can check that a resume actually restored state.
  final void Function(bool resumed)? onBoardLoaded;

  /// Fired once, the moment the last piece locks. The host screen records
  /// the completion and shows the celebration UI. It must return true only
  /// after the record is saved; false or an error keeps the progress save.
  final Future<bool> Function()? onCompleted;

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

  // Serialize progress writes so a delayed write cannot recreate a save
  // after a successful completion has deleted it.
  Future<void>? _pendingProgressSave;

  // Which game instance currently owns each save key (this app run). If the
  // player reopens a puzzle while an older session is still finishing its
  // completion bookkeeping, the new session claims the key and the old one
  // must no longer write or delete the save — it could wipe new progress.
  static final Map<String, Object> _saveKeyOwners = {};
  final Object _saveOwnerToken = Object();

  bool get _ownsSaveKey {
    final key = saveKey;
    return key == null || identical(_saveKeyOwners[key], _saveOwnerToken);
  }

  // Live piece state: the tray holds unused pieces; world holds board pieces.
  PieceTray? _tray;
  late Vector2 _boardSize;
  final List<ShapedPieceImage> _pieceImages = [];
  bool _disposed = false;

  // Toggles arrive from the host screen's buttons, possibly before onLoad
  // finishes, so the desired state is stored and applied once loading is done.
  SpriteComponent? _ghostPreview;
  bool _ghostPreviewEnabled = false;
  bool _edgesOnlyFilter = false;

  late double _fitZoom;
  double _zoomAtPinchStart = 1;

  double get _trayHeight => min(size.y * 0.18, 130);

  @override
  Color backgroundColor() => const Color(0xFF2E3440);

  @override
  Future<void> onLoad() async {
    if (_disposed) {
      return;
    }
    try {
      await _loadPuzzle();
    } catch (_) {
      _disposePieceImages();
      rethrow;
    }
  }

  Future<void> _loadPuzzle() async {
    final key = saveKey;
    if (key != null) {
      _saveKeyOwners[key] = _saveOwnerToken;
    }

    // Warm the sound cache in the background; loading must not wait on it.
    unawaited(sounds?.preload());

    final image = await images.load(imageAsset);
    if (_disposed) {
      return;
    }

    final pieceSize = Vector2(image.width / columns, image.height / rows);
    _boardSize = Vector2(image.width.toDouble(), image.height.toDouble());
    progress = PuzzleProgress(totalPieces: columns * rows);

    _addBoardOutline();
    _addGhostPreview(image);

    // Cut the photo into shaped pieces. The seed comes from the save key so
    // a resumed puzzle is re-cut exactly the same way; without a key (tests)
    // the image + grid still give one stable cut per puzzle.
    final shapes = PieceShapeGrid.generate(
      columns: columns,
      rows: rows,
      seed: shapeSeedForKey(saveKey ?? '$imageAsset.${columns}x$rows'),
    );
    final shapedImages = await rasterizePieces(
      source: image,
      columns: columns,
      rows: rows,
      shapes: shapes,
    );
    _pieceImages.addAll(shapedImages);
    // Disposal can happen while the rasterizer is still producing images.
    if (_disposed) {
      _disposePieceImages();
      return;
    }
    final allPieces = _createPieceData(shapedImages, pieceSize);
    final savedState = await _loadSavedProgress(allPieces.length);
    if (_disposed) {
      return;
    }

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
    if (savedState == null) {
      // Save right away: opening a puzzle marks it "in progress", and the
      // shuffled tray order survives an app restart instead of reshuffling.
      persistProgress();
    }
    _fitCameraToBoard();
    onBoardLoaded?.call(savedState != null);
  }

  @override
  void onDispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _disposePieceImages();
    unawaited(sounds?.dispose());
    super.onDispose();
  }

  void _disposePieceImages() {
    for (final image in _pieceImages) {
      image.dispose();
    }
    _pieceImages.clear();
  }

  /// How visible the ghost hint image is when enabled. Strong enough to
  /// guide placement, faint enough that locked pieces clearly stand out.
  static const _ghostOpacity = 0.25;

  /// A dimmed copy of the finished picture, under everything on the board.
  /// It starts invisible; [setGhostPreview] switches its visibility.
  void _addGhostPreview(ui.Image image) {
    final ghost = SpriteComponent(
      sprite: Sprite(image),
      size: _boardSize.clone(),
      priority: -3, // Below the board outline and all pieces.
    )..opacity = _ghostPreviewEnabled ? _ghostOpacity : 0;
    _ghostPreview = ghost;
    world.add(ghost);
  }

  /// Shows or hides the faint full-image hint on the board.
  void setGhostPreview(bool enabled) {
    _ghostPreviewEnabled = enabled;
    _ghostPreview?.opacity = enabled ? _ghostOpacity : 0;
  }

  /// Limits the tray to border pieces (true) or shows all pieces (false).
  void setEdgesOnlyFilter(bool enabled) {
    _edgesOnlyFilter = enabled;
    _tray?.setEdgesOnly(enabled);
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

  /// Pairs each shaped piece image with stable indexes and solved positions
  /// for saving and restoring.
  List<PieceData> _createPieceData(
    List<ShapedPieceImage> shapedImages,
    Vector2 pieceSize,
  ) {
    return [
      for (var index = 0; index < shapedImages.length; index++)
        PieceData(
          index: index,
          sprite: shapedImages[index].sprite,
          renderBleed: shapedImages[index].bleed,
          correctPosition: Vector2(
            (index % columns) * pieceSize.x,
            (index ~/ columns) * pieceSize.y,
          ),
        ),
    ];
  }

  void _addTray(List<PieceData> pieces, Vector2 pieceSize) {
    final tray = PieceTray(
      pieces: pieces,
      pieceWorldSize: pieceSize,
      isEdgePiece: (pieceIndex) => isEdgePiece(pieceIndex, columns, rows),
      position: Vector2(0, size.y - _trayHeight),
      size: Vector2(size.x, _trayHeight),
    )..setEdgesOnly(_edgesOnlyFilter);
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
      _celebrateCompletion();
    }
    persistProgress();
  }

  void _celebrateCompletion() {
    unawaited(_recordCompletion());
    sounds?.playComplete();
    HapticFeedback.heavyImpact().ignore();
    _playCompletionGlow();
  }

  Future<void> _recordCompletion() async {
    final recordCompletion = onCompleted;
    if (recordCompletion == null) {
      return;
    }
    try {
      if (!await recordCompletion()) {
        return;
      }
      await _pendingProgressSave;
      final store = saveStore;
      final key = saveKey;
      // Skip the delete if a newer session took over this puzzle meanwhile:
      // the save on disk is that session's progress, not ours to remove.
      if (store != null && key != null && _ownsSaveKey) {
        await store.delete(key);
      }
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('Puzzle completion failed; progress retained: $error');
      }
    }
  }

  /// A soft white pulse over the finished image. The host screen times its
  /// celebration card to appear as this fades out.
  void _playCompletionGlow() {
    final glow = RectangleComponent(
      size: _boardSize.clone(),
      priority: 150, // Above every piece.
      paint: Paint()..color = const Color(0x00FFFFFF),
    );
    world.add(glow);
    glow.add(
      OpacityEffect.to(
        0.7,
        EffectController(
          duration: 0.45,
          alternate: true, // Fade in, then back out.
          curve: Curves.easeOut,
        ),
        onComplete: glow.removeFromParent,
      ),
    );
  }

  /// Piece indexes still in the tray — exposed for tests.
  @visibleForTesting
  List<int> get trayPieceIndexes => _tray?.remainingPieceIndexes ?? const [];

  /// Piece indexes shown in the tray after filtering — exposed for tests.
  @visibleForTesting
  List<int> get visibleTrayPieceIndexes =>
      _tray?.visiblePieceIndexes ?? const [];

  /// The ghost hint's current opacity — exposed for tests.
  @visibleForTesting
  double get ghostPreviewOpacity => _ghostPreview?.opacity ?? 0;

  /// Lets tests wait for queued writes instead of relying on frame timing.
  @visibleForTesting
  Future<void> get progressSaved =>
      _pendingProgressSave ?? Future<void>.value();

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
      renderBleed: data.renderBleed,
      size: pieceSize.clone(),
      position: position,
      correctPosition: data.correctPosition.clone(),
    );

    for (final index in state.lockedPieceIndexes) {
      final data = allPieces[index];
      // A finished board should never be saved, but if one slips through,
      // celebrating here retries the completion record (and the save delete)
      // instead of leaving the puzzle stuck "in progress" forever.
      if (progress.lockPiece()) {
        _celebrateCompletion();
      }
      world.add(
        createPiece(data, data.correctPosition.clone())..restoreAsLocked(),
      );
    }
    for (final entry in state.loosePiecePositions.entries) {
      world.add(createPiece(allPieces[entry.key], entry.value.clone()));
    }
  }

  /// Writes progress while playing. Completion retains the last resumable
  /// snapshot until _recordCompletion confirms the permanent record is saved.
  /// Fire-and-forget: gameplay never waits on storage.
  void persistProgress() {
    final store = saveStore;
    final key = saveKey;
    if (store == null || key == null || !_ownsSaveKey) {
      return;
    }
    if (progress.isComplete) {
      return;
    }

    final state = _createSaveState();
    Future<void> writeSnapshot() async {
      try {
        await store.save(key, state);
      } on Object catch (error) {
        if (kDebugMode) {
          debugPrint('Puzzle progress save failed: $error');
        }
      }
    }

    final previousWrite = _pendingProgressSave;
    final write = previousWrite == null
        ? writeSnapshot()
        : previousWrite.then((_) => writeSnapshot());
    _pendingProgressSave = write;
    unawaited(
      write.then((_) {
        if (identical(_pendingProgressSave, write)) {
          _pendingProgressSave = null;
        }
      }),
    );
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
}
