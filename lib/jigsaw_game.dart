// Game logic overview:
// 1. onLoad loads the photo and creates columns x rows pieces. It restores
//    saved progress when available; otherwise all pieces start in the tray.
// 2. The camera controls which part of the board is visible and its zoom.
//    The tray stays fixed on screen while the board view moves or zooms.
// 3. onGameResize adjusts the tray and fits the board above it again.
// 4. Pinching or scrolling zooms around the fingers or cursor; dragging
//    empty space pans only while zoomed in. At the fitted view the board
//    stays put, and zooming back out snaps the camera home to it.
// 5. PieceGroups resolves neighbor joins, rigid drags, and whole-chunk locks.
// 6. After a chunk settles, its placed pieces are counted. At completion a glow
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
import 'piece_groups.dart';
import 'piece_renderer.dart';
import 'piece_shapes.dart';
import 'piece_tray.dart';
import 'puzzle_logic.dart';
import 'puzzle_piece.dart';
import 'puzzle_save.dart';
import 'studio_theme.dart';

/// The board uses image pixels as world units; the tray stays in screen space.
/// Pinching zooms the camera; dragging empty space pans it, but only while
/// zoomed in — at the fitted view the board never moves.
class JigsawGame extends FlameGame
    with DragCallbacks, ScaleCallbacks, ScrollCallbacks {
  JigsawGame({
    required this.imageAsset,
    required this.columns,
    required this.rows,
    this.saveStore,
    this.saveKey,
    this.startedDay,
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

  /// Day key stamped on saves of a FRESH board; a resumed board keeps the
  /// day its save carries. The daily streak reads [runStartedDay] to decide
  /// which day a finished run credits.
  final String? startedDay;

  /// The day this run actually began: [startedDay] for a fresh board, the
  /// restored save's stamp (possibly null for pre-stamp saves) for a resume.
  String? get runStartedDay => _runStartedDay;
  String? _runStartedDay;

  /// Live count of correctly placed pieces, used to detect completion.
  late final PuzzleProgress progress;

  /// Mirrors [progress] for the host screen's palette counter. A plain
  /// field notifier: each game instance (including restarts) starts at 0
  /// and needs no disposal.
  final ValueNotifier<int> placedCount = ValueNotifier(0);

  // Serialize progress writes so a delayed write cannot recreate a save
  // after a successful completion has deleted it.
  Future<void>? _pendingProgressSave;
  Future<void>? _pendingProgressDelete;
  Future<void>? _pendingCompletion;
  bool _discardingProgress = false;

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
  _ElevatedPieceOverlay? _elevatedOverlay;
  late PieceGroups _groups;
  final Map<int, PuzzlePiece> _boardPieces = {};
  final Set<int> _busyPieces = {};
  late Vector2 _boardSize;
  final List<ShapedPieceImage> _pieceImages = [];
  bool _disposed = false;

  // Toggles arrive from the host screen's buttons, possibly before onLoad
  // finishes, so the desired state is stored and applied once loading is done.
  SpriteComponent? _ghostPreview;
  bool _ghostPreviewEnabled = false;
  bool _edgesOnlyFilter = false;

  // Starts at the camera's default zoom so gestures arriving before the
  // first fit (mid-load) read "not zoomed in" instead of crashing.
  double _fitZoom = 1;
  double _zoomAtPinchStart = 1;

  // The tray takes exactly what its two rows need (six columns always fit —
  // see the tray geometry in puzzle_logic.dart), capped so the board keeps
  // most of the screen. Until the pieces are cut, the cap stands in.
  double get _trayHeight {
    final cap = min(size.y * 0.30, 200.0);
    final aspect = _traySpriteAspect;
    if (aspect == null) {
      return cap;
    }
    return min(cap, preferredTrayHeight(size.x, aspect));
  }

  double? _traySpriteAspect;

  BoardColorOption _boardColor = defaultBoardColorOption;
  RectangleComponent? _boardOutline;

  @override
  Color backgroundColor() => _boardColor.background;

  @visibleForTesting
  Color get boardOutlineColor => _boardColor.outline;

  /// Swaps the board backdrop and its outline. Safe before onLoad (the
  /// outline reads the option when added). Flame reads [backgroundColor]
  /// only while building the GameWidget — not per frame — so the host must
  /// rebuild it afterwards (GameScreen calls this inside setState).
  void setBoardColor(BoardColorOption option) {
    _boardColor = option;
    _boardOutline?.paint.color = option.outline;
  }

  @override
  Future<void> onLoad() async {
    if (_disposed || _discardingProgress) {
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
    if (_disposed || _discardingProgress) {
      return;
    }

    final pieceSize = Vector2(image.width / columns, image.height / rows);
    _groups = PieceGroups(
      columns: columns,
      rows: rows,
      cellWidth: pieceSize.x,
      cellHeight: pieceSize.y,
    );
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
    // The tray's preferred height depends on the cut pieces' aspect ratio.
    final pieceSrcSize = shapedImages.first.sprite.srcSize;
    _traySpriteAspect = pieceSrcSize.x / pieceSrcSize.y;
    // Disposal can happen while the rasterizer is still producing images.
    if (_disposed || _discardingProgress) {
      _disposePieceImages();
      return;
    }
    final allPieces = _createPieceData(shapedImages, pieceSize);
    final savedState = await _loadSavedProgress(allPieces.length);
    if (_disposed || _discardingProgress) {
      return;
    }

    final List<PieceData> trayPieces;
    if (savedState == null) {
      _runStartedDay = startedDay;
      // Start fresh: every piece goes into the tray in a random order.
      trayPieces = List.of(allPieces)..shuffle();
    } else {
      // Resume: the run keeps the day it was actually begun on.
      _runStartedDay = savedState.startedDay;
      // Restore the board and preserve the remaining tray order.
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
    // An interrupted final snap can leave a fully placed save. Finish
    // recording it after the board and its restored counter are ready.
    if (progress.isComplete) _celebrateCompletion();
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
      priority: -4, // Below the board outline and all pieces.
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
    _boardOutline = RectangleComponent(
      size: _boardSize.clone(),
      priority: -3, // Render below locked pieces.
      paint: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _boardColor.outline,
    );
    world.add(_boardOutline!);
    // Above locked pieces (-2), below loose bodies (0): a resting piece's
    // contact shadow falls on the flush picture, while a joined chunk's
    // internal shadows are covered by its own members' bodies.
    world.add(_RestShadow()..priority = -1);
    // Above resting pieces, below every dragged body: all lifted shadows
    // paint first, so a dragged chunk cannot shade its own members.
    world.add(_DragShadow()..priority = 90);
  }

  /// Whether [piece]'s resting contact shadow draws this frame. Locked
  /// pieces sit flush in the picture; elevated pieces hand off to the
  /// stronger lifted shadow in [_DragShadow].
  bool _showsRestShadow(PuzzlePiece piece) =>
      !piece.isLocked && !piece.isElevated;

  /// Piece indexes whose resting contact shadow draws this frame — exposed
  /// so tests can assert the resting/locked/dragged handoff without
  /// scraping pixels.
  @visibleForTesting
  List<int> get restShadowPieceIndexes => [
    for (final piece in _boardPieces.values)
      if (_showsRestShadow(piece)) piece.index,
  ];

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
          restShadow: shapedImages[index].restShadow,
          restShadowPad: shapedImages[index].shadowPad,
          renderBleed: shapedImages[index].bleed,
          artwork: shapedImages[index].artwork,
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
    // Above the tray, so a carried piece stays visible crossing it.
    _elevatedOverlay = _ElevatedPieceOverlay()..priority = 1;
    camera.viewport.add(_elevatedOverlay!);
  }

  /// Last size this game laid out for. GameWidget rebuilds (e.g. the board
  /// color setState) re-fire onGameResize with an unchanged size; refitting
  /// then would throw away the player's zoom and pan.
  Vector2? _lastLayoutSize;

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);

    final tray = _tray;
    if (tray == null) {
      return; // onLoad sets up the layout after loading finishes.
    }
    if (size == _lastLayoutSize) {
      return;
    }
    _lastLayoutSize = size.clone(); // Flame reuses the vector it passes in.

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
    panBy(event.canvasEndPosition - event.canvasStartPosition);
  }

  @override
  void onScaleStart(ScaleStartEvent event) {
    super.onScaleStart(event);
    _zoomAtPinchStart = camera.viewfinder.zoom;
  }

  @override
  void onScaleUpdate(ScaleUpdateEvent event) {
    panBy(event.focalPointDelta);
    // event.scale is cumulative since the gesture started.
    zoomTo(_zoomAtPinchStart * event.scale, event.canvasEndPosition);
  }

  @override
  void onScroll(ScrollEvent event) {
    const scrollPixelsPerZoomDoubling = 300;
    final zoomFactor = pow(
      2,
      -event.scrollDelta.y / scrollPixelsPerZoomDoubling,
    ).toDouble();
    zoomTo(camera.viewfinder.zoom * zoomFactor, event.canvasPosition);
  }

  /// Moves the camera opposite to a finger drag of [canvasDelta] pixels.
  /// Ignored at the fitted view: a missed piece grab must not shove the
  /// board around — panning is earned by zooming in first.
  void panBy(Vector2 canvasDelta) {
    if (!isZoomedBeyondFit(camera.viewfinder.zoom, _fitZoom)) {
      return;
    }
    camera.viewfinder.position -= canvasDelta / camera.viewfinder.zoom;
    _clampCamera();
  }

  /// Zooms toward [canvasFocalPoint], keeping it fixed on screen. Zooming
  /// back to (or below) the fit zoom snaps the camera home to the centered
  /// fitted view, so pinching out is always a way back to "board stays put".
  void zoomTo(double requestedZoom, Vector2 canvasFocalPoint) {
    final newZoom = clampZoom(requestedZoom, _fitZoom);
    if (!isZoomedBeyondFit(newZoom, _fitZoom)) {
      _fitCameraToBoard();
      return;
    }
    _zoomAroundCanvasPoint(newZoom, canvasFocalPoint);
  }

  /// Returns the camera to the centered fitted view. No UI button triggers
  /// this anymore; pinching out snaps home instead (see [zoomTo]).
  void resetView() => _fitCameraToBoard();

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

  /// Registers a new board piece, including a piece just lifted from the tray.
  void addBoardPiece(PuzzlePiece piece) {
    _boardPieces[piece.index] = piece;
    _groups.add(piece.index, Point(piece.x, piece.y), locked: piece.isLocked);
    world.add(piece);
  }

  /// Only one pointer can own a chunk. All members rise above loose pieces.
  bool beginPieceDrag(PuzzlePiece piece) {
    final members = _groups.membersOf(piece.index);
    if (_groups.isLocked(piece.index) || members.any(_busyPieces.contains)) {
      return false;
    }
    _groups.moveTo(piece.index, Point(piece.x, piece.y));
    _busyPieces.addAll(members);
    for (final index in members) {
      _boardPieces[index]!.setDragging(true);
    }
    return true;
  }

  void movePieceBy(PuzzlePiece piece, Vector2 delta) {
    _groups.translate(piece.index, Point(delta.x, delta.y));
    _syncGroupPositions(piece.index);
  }

  /// The tray owns its gesture and supplies an absolute pointer position.
  void movePieceTo(PuzzlePiece piece, Vector2 position) {
    _groups.moveTo(piece.index, Point(position.x, position.y));
    _syncGroupPositions(piece.index);
  }

  void _syncGroupPositions(int member) {
    for (final index in _groups.membersOf(member)) {
      final position = _groups.positionOf(index);
      _boardPieces[index]!.position.setValues(position.x, position.y);
    }
  }

  /// A lone piece dropped over the tray goes back into it (players clear a
  /// messy board this way). Chunks and locked pieces stay: the tray holds
  /// single pieces only. [settlePiece] resolves the drop point.
  bool _shouldReturnToTray(PuzzlePiece piece, Vector2 dropPoint) {
    final tray = _tray;
    if (tray == null || _groups.membersOf(piece.index).length > 1) {
      return false;
    }
    return dropPoint.y >= tray.position.y;
  }

  void _returnPieceToTray(PuzzlePiece piece, Vector2 dropPoint) {
    // The piece's on-screen sprite box: where the tray's landing animation
    // starts, so the return visibly continues from under the finger.
    final zoom = camera.viewfinder.zoom;
    final spriteTopLeft = camera.localToGlobal(
      piece.position - piece.renderBleed,
    );
    final flightFrom = Rect.fromLTWH(
      spriteTopLeft.x,
      spriteTopLeft.y,
      piece.sprite!.srcSize.x * zoom,
      piece.sprite!.srcSize.y * zoom,
    );
    _groups.remove(piece.index);
    _boardPieces.remove(piece.index);
    piece.removeFromParent();
    _tray!.returnPiece(
      PieceData(
        index: piece.index,
        sprite: piece.sprite!,
        restShadow: _pieceImages[piece.index].restShadow,
        restShadowPad: _pieceImages[piece.index].shadowPad,
        renderBleed: piece.renderBleed,
        artwork: piece.artwork,
        correctPosition: piece.correctPosition.clone(),
      ),
      canvasPoint: dropPoint,
      flightFrom: flightFrom,
    );
    sounds?.playDrop();
    persistProgress();
  }

  void _keepGroupClearOfTray(int member) {
    const gap = 8.0;
    final bottom = _groups
        .membersOf(member)
        .map((index) => _groups.positionOf(index).y + _groups.cellHeight)
        .reduce(max);
    final pieceBottomOnScreen = camera.localToGlobal(Vector2(0, bottom)).y;
    final maxPieceBottomOnScreen = size.y - _trayHeight - gap;
    final overlap = pieceBottomOnScreen - maxPieceBottomOnScreen;

    if (overlap > 0) {
      _groups.translate(member, Point(0.0, -overlap / camera.viewfinder.zoom));
    }
  }

  /// Both board and tray releases use the same pure chunk rules. A drop from
  /// a cancelled gesture passes [allowTrayReturn] false: it was never a
  /// deliberate release, so it may not send the piece back to the tray.
  void settlePiece(PuzzlePiece piece, {bool allowTrayReturn = true}) {
    if (_disposed || _discardingProgress) return;
    if (piece.isLocked || piece.isSettling) return;
    _groups.moveTo(piece.index, Point(piece.x, piece.y));
    _busyPieces.removeAll(_groups.membersOf(piece.index));
    // The finger decides where the drop lands, not the piece's center: a
    // piece grabbed by its edge can hang over the tray while the finger is
    // still clearly on the board. Non-gesture drops (no known pointer) fall
    // back to the center.
    final dropPoint = piece.takeDragPointer() ??
        camera.localToGlobal(piece.position + piece.size / 2);
    if (allowTrayReturn && _shouldReturnToTray(piece, dropPoint)) {
      _returnPieceToTray(piece, dropPoint);
      return;
    }
    final result = _groups.drop(
      piece.index,
      boardTolerance: piece.size.x * snapToleranceFraction,
      unavailable: _busyPieces,
    );
    if (!result.locked) _keepGroupClearOfTray(piece.index);

    if (!result.joined && !result.locked) {
      _syncGroupPositions(piece.index);
      for (final index in result.members) {
        _boardPieces[index]!.setDragging(false);
      }
      sounds?.playDrop();
      persistProgress();
      return;
    }

    // Saves commit the accepted group lock and exact coordinates now;
    // leaving during the visual glide must not lose the placement.
    _busyPieces.addAll(result.members);
    var remaining = result.members.length;
    for (final index in result.members) {
      final target = _groups.positionOf(index);
      _boardPieces[index]!.animateSettle(
        Vector2(target.x, target.y),
        onComplete: () {
          if (--remaining == 0) _finishGroupSettle(result);
        },
      );
    }
    persistProgress();
  }

  void _finishGroupSettle(GroupDrop result) {
    if (_disposed || _discardingProgress) return;
    _busyPieces.removeAll(result.members);
    var completed = false;
    // Set all member flags and count them before saving: no partial lock save.
    for (final index in result.members) {
      final piece = _boardPieces[index]!;
      final newlyLocked = result.locked && !piece.isLocked;
      piece.finishSettle(locked: result.locked);
      if (newlyLocked) completed = progress.lockPiece() || completed;
    }
    placedCount.value = progress.lockedCount;
    sounds?.playSnap();
    HapticFeedback.lightImpact().ignore();
    if (completed) _celebrateCompletion();
    persistProgress();
  }

  void _celebrateCompletion() {
    unawaited(_pendingCompletion = _recordCompletion());
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
      if (store != null &&
          key != null &&
          _ownsSaveKey &&
          !_discardingProgress) {
        await (_pendingProgressDelete = store.delete(key));
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

  /// Pieces riding above everything (dragged or glide-settling); the tray
  /// overlay re-renders exactly these.
  @visibleForTesting
  Iterable<PuzzlePiece> get elevatedPieces =>
      _boardPieces.values.where((piece) => piece.isElevated);

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

  /// The tray-crossing re-render layer — exposed for tests.
  @visibleForTesting
  Component get elevatedPieceOverlay => _elevatedOverlay!;

  /// Completes when the currently queued progress writes have landed.
  /// Use [discardProgress] to stop further writes before deleting a save.
  Future<void> get progressSaved =>
      _pendingProgressSave ?? Future<void>.value();

  /// Completes after the current completion-record and save-cleanup attempt.
  Future<void> get completionFinished =>
      _pendingCompletion ?? Future<void>.value();

  /// Permanently stops this run and clears its progress before replacement.
  /// Late gesture releases and loads must not create any more snapshots.
  Future<void> discardProgress() async {
    _discardingProgress = true;
    pauseEngine();
    await progressSaved;
    // Completion may already have issued a delete before restart began.
    // Drain that too, so it cannot erase the replacement game's first save.
    await _pendingProgressDelete;
    final store = saveStore;
    final key = saveKey;
    if (store != null && key != null && _ownsSaveKey) {
      await store.delete(key);
    }
  }

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
      artwork: data.artwork,
      size: pieceSize.clone(),
      position: position,
      correctPosition: data.correctPosition.clone(),
    );

    for (final index in state.lockedPieceIndexes) {
      final data = allPieces[index];
      addBoardPiece(
        createPiece(data, data.correctPosition.clone())..restoreAsLocked(),
      );
    }
    for (final entry in state.loosePiecePositions.entries) {
      addBoardPiece(createPiece(allPieces[entry.key], entry.value.clone()));
    }
    final positions = {
      for (final piece in _boardPieces.values)
        piece.index: Point(piece.x, piece.y),
    };
    // Flame's Vector2 (including the existing save parser) stores Float32.
    // Allow only its rounding error when recovering exact relative offsets.
    // Two relative machine epsilons cover both positions and solved cells.
    _groups.restore(
      positions: positions,
      lockedPieces: state.lockedPieceIndexes,
      relativePositionRoundoff: 2 * 1.1920928955078125e-7,
    );
    for (final piece in _boardPieces.values) {
      final position = _groups.positionOf(piece.index);
      piece.position.setValues(position.x, position.y);
      if (_groups.isLocked(piece.index)) {
        piece.restoreAsLocked();
        progress.lockPiece();
      }
    }
    placedCount.value = progress.lockedCount;
  }

  /// Writes progress while playing. Completion retains the last resumable
  /// snapshot until _recordCompletion confirms the permanent record is saved.
  /// Fire-and-forget: gameplay never waits on storage.
  void persistProgress() {
    if (_disposed || _discardingProgress) return;
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

  /// Screen-space top of the tray, for the overlay's "is it over the tray"
  /// check. Infinity while the tray is not mounted (nothing to cover).
  double get _trayTopOnScreen => _tray?.position.y ?? double.infinity;

  /// Copies the live board and tray state into a snapshot for storage.
  PuzzleSaveState _createSaveState() {
    final lockedPieceIndexes = <int>[];
    final loosePiecePositions = <int, Vector2>{};
    for (final piece in _boardPieces.values) {
      // The visual lock flag follows the snap animation. The group's lock
      // already records whether this drop reached its final board position.
      if (_groups.isLocked(piece.index)) {
        lockedPieceIndexes.add(piece.index);
      } else {
        loosePiecePositions[piece.index] = piece.position.clone();
      }
    }
    return PuzzleSaveState(
      trayPieceIndexes: _tray?.remainingPieceIndexes ?? const [],
      lockedPieceIndexes: lockedPieceIndexes,
      loosePiecePositions: loosePiecePositions,
      startedDay: _runStartedDay,
    );
  }
}

/// Re-renders elevated pieces (dragged or glide-settling) above the tray.
/// Pieces live in the world and the tray is a near-opaque viewport HUD, so
/// without this a piece carried across the tray slides underneath its wood
/// and seems to vanish mid-drag. Render-only: hit testing and game logic
/// keep using the world piece; pixels away from the tray are untouched.
class _ElevatedPieceOverlay extends Component
    with HasGameReference<JigsawGame> {
  @override
  void render(Canvas canvas) {
    final trayTop = game._trayTopOnScreen;
    if (!trayTop.isFinite) return;
    // Above the tray the world copy is already visible. Repainting its
    // partially transparent edge there would darken it a second time.
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(0, trayTop, game.size.x, game.size.y - trayTop),
      doAntiAlias: false,
    );
    final zoom = game.camera.viewfinder.zoom;
    final elevated = game._boardPieces.values
        .where((piece) => piece.isElevated)
        .toList();
    // Shadows first, bodies second — same layering as the world, so a
    // dragged chunk's members never shade each other here either.
    for (final renderBody in [false, true]) {
      for (final piece in elevated) {
        final topLeft = game.camera.localToGlobal(piece.position);
        // Both passes include the glide offset, which can still cross the
        // tray even when the piece's final position is already above it.
        canvas.save();
        canvas.translate(topLeft.x, topLeft.y);
        canvas.scale(zoom);
        if (renderBody) {
          piece.render(canvas);
        } else {
          piece.renderDropShadow(canvas);
        }
        canvas.restore();
      }
    }
    canvas.restore();
  }
}

/// World layer between locked and loose pieces: blits every resting piece's
/// baked contact shadow. Below the bodies, a joined chunk's internal shadows
/// are hidden by its own members, so only the chunk's outer silhouette is
/// shaded — and above locked pieces, so a loose piece still visibly sits on
/// top of the finished picture.
class _RestShadow extends Component with HasGameReference<JigsawGame> {
  // The half-resolution shadow upscales 2x plus camera zoom; the default
  // FilterQuality.none bands its gradient into visible steps.
  static final _paint = Paint()
    ..filterQuality = FilterQuality.medium
    ..isAntiAlias = true;

  @override
  void render(Canvas canvas) {
    for (final piece in game._boardPieces.values) {
      if (!game._showsRestShadow(piece)) {
        continue;
      }
      final image = game._pieceImages[piece.index];
      final pad = image.shadowPad;
      image.restShadow.render(
        canvas,
        // The shadow box is the sprite box grown by pad on every side.
        position: piece.position - piece.renderBleed - Vector2.all(pad),
        size: piece.sprite!.srcSize + Vector2.all(2 * pad),
        overridePaint: _paint,
      );
    }
  }
}

/// World layer between resting pieces and dragged bodies: paints every
/// elevated piece's drop shadow, so all shadows land below all carried
/// artwork instead of on a chunk-mate's face.
class _DragShadow extends Component with HasGameReference<JigsawGame> {
  @override
  void render(Canvas canvas) {
    for (final piece in game._boardPieces.values) {
      if (!piece.isElevated) {
        continue;
      }
      canvas.save();
      canvas.translate(piece.position.x, piece.position.y);
      piece.renderDropShadow(canvas);
      canvas.restore();
    }
  }
}
