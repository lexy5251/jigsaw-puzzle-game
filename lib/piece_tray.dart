// Tray logic overview:
// 1. Show the remaining pieces as two stacked rows of small previews,
//    filling each column top-to-bottom before moving right.
// 2. Drag sideways to scroll, or drag a preview above the tray to lift it.
// 3. Replace the preview with a board piece that follows the pointer.
// 4. On release or cancellation, ask the piece to settle and clear drag state.
//
// The tray uses screen coordinates; lifted pieces use board (world) coordinates.

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

import 'jigsaw_game.dart';
import 'puzzle_logic.dart';
import 'puzzle_piece.dart';
import 'studio_theme.dart';

/// The image region and solved position needed to create a board piece.
class PieceData {
  PieceData({
    required this.index,
    required this.sprite,
    required this.renderBleed,
    required this.correctPosition,
  });

  /// Canonical piece number (row * columns + column); save files reference it.
  final int index;

  /// The shaped piece image: the base cell plus [renderBleed] margin all
  /// around, so tabs that stick out past the cell are included.
  final Sprite sprite;

  /// How far [sprite] extends past the base cell on each axis.
  final Vector2 renderBleed;

  /// World position of the piece's top-left corner when solved.
  final Vector2 correctPosition;
}

/// Scrollable previews of unplaced pieces, fixed at the bottom of the screen.
class PieceTray extends PositionComponent
    with DragCallbacks, HasGameReference<JigsawGame> {
  PieceTray({
    required List<PieceData> pieces,
    required this.pieceWorldSize,
    required this.isEdgePiece,
    required super.position,
    required super.size,
  }) : _remainingPieces = List.of(pieces);

  // Row count, column density, and spacing live in puzzle_logic.dart
  // (trayRows, trayVisibleColumns, trayPadding, traySlotGap).
  static const _liftDistanceAboveTray = 4.0;

  /// Full size on the board; tray previews preserve this aspect ratio.
  final Vector2 pieceWorldSize;

  /// Tells the tray which piece indexes belong to the puzzle border,
  /// so the edges-only filter can work without knowing the grid size.
  final bool Function(int pieceIndex) isEdgePiece;

  final List<PieceData> _remainingPieces;

  /// Thumbnails currently shown — only the filtered subset when
  /// edges-only is on. [_remainingPieces] always holds every unused piece.
  final List<_TrayThumbnail> _thumbnails = [];
  bool _edgesOnly = false;
  bool _filterRebuildPending = false;

  final _thumbnailStrip = PositionComponent();
  double _scrollOffset = 0;

  int? _activePointerId;
  _TrayThumbnail? _selectedThumbnail;
  PuzzlePiece? _carriedPiece;

  late final RectangleComponent _background;
  late final ClipComponent _trayClip;

  double get _thumbnailHeight =>
      trayThumbnailHeight(size.x, size.y, _thumbnailAspect);
  double get _rowSlotHeight => _thumbnailHeight + trayPadding;

  // Previews show the shaped piece images, which carry a transparent bleed
  // margin around the base cell — use their aspect ratio, not the cell's,
  // so the shapes aren't stretched.
  double get _thumbnailAspect {
    final sprites = _remainingPieces;
    if (sprites.isEmpty) {
      return pieceWorldSize.x / pieceWorldSize.y;
    }
    final srcSize = sprites.first.sprite.srcSize;
    return srcSize.x / srcSize.y;
  }

  double get _thumbnailWidth => _thumbnailHeight * _thumbnailAspect;
  double get _thumbnailSlotWidth => _thumbnailWidth + traySlotGap;
  int get _columnCount => (_thumbnails.length + trayRows - 1) ~/ trayRows;
  double get _stripWidth => trayPadding + _columnCount * _thumbnailSlotWidth;

  bool get isEmpty => _remainingPieces.isEmpty;

  /// Piece indexes still in the tray, in display order (used by saves).
  /// Always the full list, regardless of the edges-only filter.
  List<int> get remainingPieceIndexes => [
    for (final data in _remainingPieces) data.index,
  ];

  /// Piece indexes currently shown in the strip (the filtered subset).
  List<int> get visiblePieceIndexes => [
    for (final thumbnail in _thumbnails) thumbnail.data.index,
  ];

  @override
  Future<void> onLoad() async {
    _background = RectangleComponent(
      size: size.clone(),
      paint: Paint()..color = StudioColors.tray,
    );
    add(_background);

    // Hide the parts of the scrolling strip that extend outside the tray.
    _trayClip = ClipComponent.rectangle(size: size.clone());
    _trayClip.add(_thumbnailStrip);
    add(_trayClip);

    _rebuildThumbnails();
  }

  /// Takes a piece back from the board, inserting it at the slot under
  /// [canvasPoint] — the piece must reappear where the player dropped it,
  /// not at the strip's (possibly scrolled-off) far end.
  void returnPiece(PieceData data, {required Vector2 canvasPoint}) {
    final slot = _slotIndexAt(canvasPoint);
    final insertAt = slot < 0
        ? 0
        : slot >= _thumbnails.length
        ? _remainingPieces.length
        : _remainingPieces.indexOf(_thumbnails[slot].data);
    _remainingPieces.insert(insertAt, data);
    _rebuildThumbnails();
  }

  /// Shows only edge pieces (true) or every unused piece (false).
  void setEdgesOnly(bool enabled) {
    if (_edgesOnly == enabled) {
      return;
    }
    _edgesOnly = enabled;
    if (isLoaded) {
      // Keep the selected thumbnail alive until this pointer releases it.
      if (_activePointerId != null) {
        _filterRebuildPending = true;
      } else {
        _rebuildThumbnails();
      }
    }
  }

  /// Recreates the thumbnail strip from the current filter and remaining
  /// pieces. Cheap enough to rebuild wholesale on every filter change.
  void _rebuildThumbnails() {
    for (final thumbnail in _thumbnails) {
      thumbnail.removeFromParent();
    }
    _thumbnails.clear();

    for (final pieceData in _remainingPieces) {
      if (_edgesOnly && !isEdgePiece(pieceData.index)) {
        continue;
      }
      final thumbnail = _TrayThumbnail(
        data: pieceData,
        size: Vector2(_thumbnailWidth, _thumbnailHeight),
      );
      _thumbnails.add(thumbnail);
      _thumbnailStrip.add(thumbnail);
    }
    _layoutThumbnails();
  }

  void resizeTo({required Vector2 position, required Vector2 size}) {
    this.position = position;
    this.size = size;

    if (!isLoaded) {
      return; // onLoad will build the components using the updated size.
    }

    _background.size = size.clone();
    _trayClip.size = size.clone();
    for (final thumbnail in _thumbnails) {
      thumbnail.size = Vector2(_thumbnailWidth, _thumbnailHeight);
    }
    _layoutThumbnails();
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);

    if (_activePointerId != null) {
      return;
    }

    _activePointerId = event.pointerId;
    _selectedThumbnail = _thumbnailAtCanvasPoint(event.canvasPosition);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (event.pointerId != _activePointerId) {
      return;
    }

    // Canvas coordinates stay valid outside the tray. In Flame 1.38,
    // canvasStartPosition is the current pointer position; the end adds delta.
    final pointerPosition = event.canvasStartPosition;
    final carriedPiece = _carriedPiece;

    if (carriedPiece != null) {
      _movePieceToPointer(carriedPiece, pointerPosition);
      return;
    }

    final selectedThumbnail = _selectedThumbnail;
    final liftBoundaryY = position.y - _liftDistanceAboveTray;
    if (selectedThumbnail != null && pointerPosition.y < liftBoundaryY) {
      _liftPieceOntoBoard(selectedThumbnail, pointerPosition);
      return;
    }

    final horizontalDelta =
        event.canvasEndPosition.x - event.canvasStartPosition.x;
    // Dragging left increases the offset, revealing pieces to the right.
    _setScrollOffset(_scrollOffset - horizontalDelta);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);

    if (event.pointerId != _activePointerId) {
      return;
    }

    _finishDrag();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);

    if (event.pointerId != _activePointerId) {
      return;
    }

    _finishDrag();
  }

  void _finishDrag() {
    _carriedPiece?.settle();
    _carriedPiece = null;
    _selectedThumbnail = null;
    _activePointerId = null;
    if (_filterRebuildPending) {
      _filterRebuildPending = false;
      _rebuildThumbnails();
    }
  }

  // The tray owns this drag until release, even after the piece leaves it.
  void _liftPieceOntoBoard(_TrayThumbnail thumbnail, Vector2 canvasPosition) {
    final piece = PuzzlePiece(
      index: thumbnail.data.index,
      sprite: thumbnail.data.sprite,
      renderBleed: thumbnail.data.renderBleed,
      size: pieceWorldSize.clone(),
      position: Vector2.zero(),
      correctPosition: thumbnail.data.correctPosition,
    )..priority = 100;
    game.addBoardPiece(piece);
    game.beginPieceDrag(piece);
    _carriedPiece = piece;
    _movePieceToPointer(piece, canvasPosition);

    _remainingPieces.remove(thumbnail.data);
    _thumbnails.remove(thumbnail);
    thumbnail.removeFromParent();
    _selectedThumbnail = null;
    _layoutThumbnails();
  }

  void _movePieceToPointer(PuzzlePiece piece, Vector2 canvasPosition) {
    final pointerInWorld = game.camera.globalToLocal(canvasPosition);
    // Piece positions refer to their top-left corner; center it on the pointer.
    game.movePieceTo(piece, pointerInWorld - pieceWorldSize / 2);
  }

  void _setScrollOffset(double offset) {
    _scrollOffset = clampTrayScroll(offset, _stripWidth, size.x);
    _thumbnailStrip.x = -_scrollOffset;
  }

  void _layoutThumbnails() {
    for (final (index, thumbnail) in _thumbnails.indexed) {
      thumbnail.position = Vector2(
        trayPadding + (index ~/ trayRows) * _thumbnailSlotWidth,
        trayPadding + (index % trayRows) * _rowSlotHeight,
      );
    }

    // Resizing or removing a piece can reduce the allowed scroll distance.
    _setScrollOffset(_scrollOffset);
  }

  /// Column-major grid slot under a canvas point. Negative left of the
  /// strip; may exceed the current thumbnail count on the right.
  int _slotIndexAt(Vector2 canvasPosition) {
    final positionInStrip = canvasPosition.x - position.x + _scrollOffset;
    final column = (positionInStrip - trayPadding) ~/ _thumbnailSlotWidth;
    if (column < 0) {
      return -1;
    }

    // Split each padding gap at its midpoint so touches pick the nearest row.
    // Clamping keeps touches in the outer padding forgiving too.
    final rawRow =
        (canvasPosition.y - position.y - trayPadding / 2) ~/ _rowSlotHeight;
    final row = rawRow < 0 ? 0 : (rawRow >= trayRows ? trayRows - 1 : rawRow);
    return column * trayRows + row;
  }

  _TrayThumbnail? _thumbnailAtCanvasPoint(Vector2 canvasPosition) {
    final thumbnailIndex = _slotIndexAt(canvasPosition);
    if (thumbnailIndex < 0 || thumbnailIndex >= _thumbnails.length) {
      return null;
    }
    return _thumbnails[thumbnailIndex];
  }

  /// Strip-local top-left corners of the visible thumbnails, in order.
  @visibleForTesting
  List<Vector2> get thumbnailPositions => [
    for (final thumbnail in _thumbnails) thumbnail.position.clone(),
  ];

  /// Current thumbnail sprite-box size.
  @visibleForTesting
  Vector2 get thumbnailSize => Vector2(_thumbnailWidth, _thumbnailHeight);

  /// How far the strip is scrolled to the right.
  @visibleForTesting
  double get scrollOffset => _scrollOffset;
}

class _TrayThumbnail extends SpriteComponent {
  _TrayThumbnail({required this.data, required super.size})
    : super(sprite: data.sprite);

  final PieceData data;
}
