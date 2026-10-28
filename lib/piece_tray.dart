// Tray logic overview:
// 1. Show the remaining pieces as a horizontal row of small previews.
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

  static const _padding = 10.0;
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

  double get _thumbnailHeight => size.y - _padding * 2;

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
  double get _thumbnailSlotWidth => _thumbnailWidth + _padding;
  double get _stripWidth => _padding + _thumbnails.length * _thumbnailSlotWidth;

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
      paint: Paint()..color = const Color(0xE01B2028),
    );
    add(_background);

    // Hide the parts of the scrolling strip that extend outside the tray.
    _trayClip = ClipComponent.rectangle(size: size.clone());
    _trayClip.add(_thumbnailStrip);
    add(_trayClip);

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
    game.world.add(piece);
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
    piece.position = pointerInWorld - pieceWorldSize / 2;
  }

  void _setScrollOffset(double offset) {
    _scrollOffset = clampTrayScroll(offset, _stripWidth, size.x);
    _thumbnailStrip.x = -_scrollOffset;
  }

  void _layoutThumbnails() {
    for (final (index, thumbnail) in _thumbnails.indexed) {
      thumbnail.position = Vector2(
        _padding + index * _thumbnailSlotWidth,
        _padding,
      );
    }

    // Resizing or removing a piece can reduce the allowed scroll distance.
    _setScrollOffset(_scrollOffset);
  }

  _TrayThumbnail? _thumbnailAtCanvasPoint(Vector2 canvasPosition) {
    final positionInStrip = canvasPosition.x - position.x + _scrollOffset;
    final thumbnailIndex = (positionInStrip - _padding) ~/ _thumbnailSlotWidth;

    if (thumbnailIndex < 0 || thumbnailIndex >= _thumbnails.length) {
      return null;
    }

    return _thumbnails[thumbnailIndex];
  }
}

class _TrayThumbnail extends SpriteComponent {
  _TrayThumbnail({required this.data, required super.size})
    : super(sprite: data.sprite);

  final PieceData data;
}
