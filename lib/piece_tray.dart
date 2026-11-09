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

import 'drag_cancellation.dart';
import 'jigsaw_game.dart';
import 'piece_renderer.dart';
import 'puzzle_logic.dart';
import 'puzzle_piece.dart';
import 'studio_theme.dart';

/// The image region and solved position needed to create a board piece.
class PieceData {
  PieceData({
    required this.index,
    required this.sprite,
    required this.restShadow,
    required this.restShadowPad,
    required this.renderBleed,
    required this.correctPosition,
    this.artwork,
  });

  /// Canonical piece number (row * columns + column); save files reference it.
  final int index;

  /// The shaped piece image: the base cell plus [renderBleed] margin all
  /// around, so tabs that stick out past the cell are included.
  final Sprite sprite;

  /// The piece's baked contact shadow, drawn under tray previews so a piece
  /// looks the same in the tray as resting on the board.
  final Sprite restShadow;

  /// How far [restShadow]'s box extends past [sprite]'s box on each side,
  /// in source pixels (blur spill room); blits scale and offset by this.
  final double restShadowPad;

  /// Original photo and outline for a sharp, dimensional tray preview.
  final PieceArtwork? artwork;

  /// How far [sprite] extends past the base cell on each axis.
  final Vector2 renderBleed;

  /// World position of the piece's top-left corner when solved.
  final Vector2 correctPosition;
}

/// Scrollable previews of unplaced pieces, fixed at the bottom of the screen.
class PieceTray extends PositionComponent
    with DragCallbacks, CancelAwareDrag, HasGameReference<JigsawGame> {
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

  // A just-returned piece's landing animation. Lives on the tray (not the
  // thumbnail) so a mid-flight strip rebuild still finds it: the flying
  // piece's slot renders blank until the flight lands.
  _ReturnFlight? _activeFlight;

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
  ///
  /// With [flightFrom] (the piece's on-screen sprite box) the piece visibly
  /// shrinks and glides into its slot instead of swapping in the same frame.
  /// The model commits immediately either way: saves and piece counts must
  /// never wait on a visual.
  void returnPiece(PieceData data, {required Vector2 canvasPoint, Rect? flightFrom}) {
    // A second return while one is still flying reveals the first at once;
    // one blank slot and one flyer at a time keeps the bookkeeping simple.
    _activeFlight?.finishNow();
    final slot = _slotIndexAt(canvasPoint);
    final insertAt = slot < 0
        ? 0
        : slot >= _thumbnails.length
        ? _remainingPieces.length
        : _remainingPieces.indexOf(_thumbnails[slot].data);
    _remainingPieces.insert(insertAt, data);
    _rebuildThumbnails();
    if (flightFrom != null) {
      _startReturnFlight(data, flightFrom);
    }
  }

  void _startReturnFlight(PieceData data, Rect flightFromOnCanvas) {
    final from = flightFromOnCanvas.shift(Offset(-position.x, -position.y));

    // Re-read every tick: the strip can scroll or re-layout under the flyer
    // mid-flight, and the slot must stay the true landing spot. Null once
    // the thumbnail is gone (lifted back out or filtered away) — the flight
    // then lands immediately instead of flying a ghost into an empty slot.
    // Null at launch instead means the edges-only filter hides the returned
    // piece, and the flight dissolves at the drop point.
    Rect? slotRect() {
      final destination = _thumbnails
          .where((thumbnail) => thumbnail.data.index == data.index)
          .firstOrNull;
      if (destination == null) {
        return null;
      }
      return Rect.fromLTWH(
        destination.x - _scrollOffset,
        destination.y,
        destination.width,
        destination.height,
      );
    }

    final flight = _ReturnFlight(
      pieceIndex: data.index,
      sprite: data.sprite,
      restShadow: data.restShadow,
      restShadowPad: data.restShadowPad,
      artwork: data.artwork,
      from: from,
      resolveTo: slotRect,
      onLanded: () => _activeFlight = null,
    );
    _activeFlight = flight;
    // Above the background and the clipped strip, so the flyer may overhang
    // the tray's top edge while it comes in from the board.
    add(flight..priority = 1);
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
        tray: this,
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
    // A relayout invalidates a flying piece's endpoints; land it at once.
    _activeFlight?.finishNow();
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

  void _finishDrag() {
    _carriedPiece?.settle(allowTrayReturn: !dragWasCancelled);
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
      artwork: thumbnail.data.artwork,
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
    // The tray owns this gesture, so it reports the finger for the piece.
    piece.noteDragPointer(canvasPosition);
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

  /// The piece whose landing animation is still in flight, if any.
  @visibleForTesting
  int? get landingPieceIndex => _activeFlight?.pieceIndex;

  /// Where the active landing flight is currently heading (tray-local), or
  /// null when nothing is in flight.
  @visibleForTesting
  Rect? get activeFlightTarget => _activeFlight?.target;

  /// The box the active landing flight is drawn in this frame (tray-local),
  /// or null when nothing is in flight.
  @visibleForTesting
  Rect? get activeFlightBox => _activeFlight?.currentBox;

  /// A tray piece's artwork — exposed so render tests can rebuild the
  /// expected preview pixels with PieceArtwork.render directly.
  @visibleForTesting
  PieceArtwork? artworkFor(int index) => _remainingPieces
      .where((data) => data.index == index)
      .firstOrNull
      ?.artwork;

  /// A tray piece's baked contact shadow — exposed for the same render tests.
  @visibleForTesting
  Sprite? restShadowFor(int index) => _remainingPieces
      .where((data) => data.index == index)
      .firstOrNull
      ?.restShadow;

  /// The shadow box's overhang past the sprite box (source px) — exposed so
  /// render tests can place the shadow exactly like the tray does.
  @visibleForTesting
  double? restShadowPadFor(int index) => _remainingPieces
      .where((data) => data.index == index)
      .firstOrNull
      ?.restShadowPad;

  /// A tray piece's sprite-box size in source px — the scale reference the
  /// shadow-pad math uses; exposed for the same render tests.
  @visibleForTesting
  Vector2? spriteSrcSizeFor(int index) => _remainingPieces
      .where((data) => data.index == index)
      .firstOrNull
      ?.sprite
      .srcSize;
}

class _TrayThumbnail extends SpriteComponent {
  _TrayThumbnail({required this.data, required this.tray, required super.size})
    : super(sprite: data.sprite) {
    // Thumbnails draw the sprite well below 1:1; mipmapped sampling (medium)
    // keeps the minified rim clean — the default aliases it into a visible
    // light edge on device.
    paint.filterQuality = FilterQuality.medium;
    paint.isAntiAlias = true;
  }

  final PieceData data;
  final PieceTray tray;

  @override
  void render(Canvas canvas) {
    // The slot stays blank while its piece is still flying in (returnPiece's
    // landing animation draws the artwork instead).
    if (data.index == tray._activeFlight?.pieceIndex) {
      return;
    }
    // A large puzzle may have hundreds of previews in the clipped strip;
    // only the visible columns need to draw at all.
    if (!trayColumnVisible(
      left: x,
      width: width,
      scrollOffset: tray._scrollOffset,
      viewWidth: tray.width,
    )) {
      return;
    }
    // Same contact shadow as a piece resting on the board, so moving a piece
    // between tray and board never changes how it looks. The shadow box is
    // the sprite box grown by the pad, scaled down with the preview.
    final padX = data.restShadowPad * width / data.sprite.srcSize.x;
    final padY = data.restShadowPad * height / data.sprite.srcSize.y;
    data.restShadow.render(
      canvas,
      position: Vector2(-padX, -padY),
      size: Vector2(width + 2 * padX, height + 2 * padY),
      overridePaint: paint,
    );
    final artwork = data.artwork;
    if (artwork == null) {
      super.render(canvas);
      return;
    }
    // The baked sprite holds only this piece's small crop of the photo, so
    // on dense grids (216: ~89px of photo) the constant-size tray would
    // upscale it past its resolution and look blurry. Drawing live from the
    // full photo keeps previews sharp at every piece count; the decoration
    // scale is derived from the bake so the rim stays exactly as thick as
    // on resting board pieces.
    final bounds = Rect.fromLTWH(0, 0, width, height);
    artwork.render(
      canvas,
      bounds: bounds,
      decorationScale: artwork.bakedDecorationScale(bounds),
      photoPaint: paint,
    );
  }
}

/// A returned piece flying into its tray slot: the sprite shrinks from the
/// board drop point into the destination thumbnail's box, which is revealed
/// on landing. Render-only — the tray's model committed when the flight
/// started, so interrupting it can never lose the piece.
class _ReturnFlight extends PositionComponent {
  _ReturnFlight({
    required this.pieceIndex,
    required this.sprite,
    required this.restShadow,
    required this.restShadowPad,
    required this.artwork,
    required this.from,
    required Rect? Function() resolveTo,
    required this.onLanded,
  }) {
    // A null slot at launch means the piece has no visible destination (the
    // edges-only filter hides it): dissolve at the drop point instead, and
    // freeze the resolver so the fade can never redirect to a slot that
    // appears mid-flight.
    final initialSlot = resolveTo();
    fadeOut = initialSlot == null;
    final fadeTarget = Rect.fromCenter(
      center: from.center,
      width: 0,
      height: 0,
    );
    _target = initialSlot ?? fadeTarget;
    _resolveTo = fadeOut ? () => fadeTarget : resolveTo;
    // Same mipmapped sampling as the thumbnails: the sprite shrinks well
    // below 1:1 during the flight.
    _paint.filterQuality = FilterQuality.medium;
    _paint.isAntiAlias = true;
  }

  /// The piece this flight is delivering; its tray slot renders blank until
  /// the flight lands.
  final int pieceIndex;

  final Sprite sprite;

  /// The piece's baked contact shadow — flown along under the body so the
  /// piece looks grounded the whole way into its slot.
  final Sprite restShadow;

  /// Shadow-box overhang past the sprite box, in source pixels.
  final double restShadowPad;

  /// Full-resolution piece artwork; the landing flight renders it live so it
  /// arrives as sharp as the (live-rendered) thumbnail it becomes.
  final PieceArtwork? artwork;
  final Rect from;

  /// Live destination slot in tray coordinates. Null means the slot is gone
  /// (its thumbnail was lifted or filtered away), which lands the flight.
  late final Rect? Function() _resolveTo;

  /// True when there was no visible destination slot at launch (edges-only
  /// filter): the piece dissolves at the drop point instead of landing.
  late final bool fadeOut;
  final VoidCallback onLanded;

  final Paint _paint = Paint();
  late Rect _target;
  double _elapsed = 0;
  bool _done = false;
  static const _duration = 0.18;

  /// Where the flight is currently heading — exposed for tests via the tray.
  Rect get target => _target;

  double get _progress =>
      Curves.easeOut.transform((_elapsed / _duration).clamp(0.0, 1.0));

  /// The box drawn this frame, interpolated between [from] and the live
  /// target — exposed for tests via the tray.
  Rect get currentBox => Rect.lerp(from, _target, _progress)!;

  /// Lands immediately — used when a relayout or a newer return invalidates
  /// this flight's endpoints.
  void finishNow() => _finish();

  void _finish() {
    if (_done) {
      return;
    }
    _done = true;
    onLanded();
    removeFromParent();
  }

  @override
  void update(double dt) {
    super.update(dt);
    final liveTarget = _resolveTo();
    if (liveTarget == null) {
      _finish();
      return;
    }
    _target = liveTarget;
    _elapsed += dt;
    if (_elapsed >= _duration) {
      _finish();
    }
  }

  @override
  void render(Canvas canvas) {
    // Removal is queued, so a flight finished during update is still mounted
    // for this frame's render — and the revealed thumbnail already draws.
    // Painting here too would double the piece for one frame.
    if (_done) {
      return;
    }
    final box = currentBox;
    final liveArtwork = artwork;
    if (!fadeOut && liveArtwork != null) {
      // The shadow rides along under the body, so the landing piece looks
      // grounded exactly like the thumbnail that takes over on landing. Its
      // box is the sprite box grown by the pad, scaled with the flyer.
      final padX = restShadowPad * box.width / sprite.srcSize.x;
      final padY = restShadowPad * box.height / sprite.srcSize.y;
      restShadow.render(
        canvas,
        position: Vector2(box.left - padX, box.top - padY),
        size: Vector2(box.width + 2 * padX, box.height + 2 * padY),
        overridePaint: _paint,
      );
      liveArtwork.render(
        canvas,
        bounds: box,
        // Sized for the destination slot, so the edge is already as thick as
        // the thumbnail's when it takes over on landing.
        decorationScale: liveArtwork.bakedDecorationScale(_target),
        photoPaint: _paint,
      );
      return;
    }
    if (fadeOut) {
      // The fade stays a sprite blit: the paint's alpha must dim the whole
      // piece, and as photoPaint it would dim only the photo, not the rim.
      _paint.color = Colors.white.withValues(alpha: 1 - _progress);
    }
    sprite.render(
      canvas,
      position: Vector2(box.left, box.top),
      size: Vector2(box.width, box.height),
      overridePaint: _paint,
    );
  }
}
