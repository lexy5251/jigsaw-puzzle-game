// Piece logic overview:
// Gestures delegate to the game's chunk model; this component owns only its
// shaped drawing, base-cell hit target, and visual settle feedback.
//
// All piece positions use board (world) coordinates.

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

import 'drag_cancellation.dart';
import 'jigsaw_game.dart';
import 'piece_renderer.dart';

/// A board piece that can be dragged until it snaps into its correct position.
class PuzzlePiece extends SpriteComponent
    with DragCallbacks, CancelAwareDrag, HasGameReference<JigsawGame> {
  PuzzlePiece({
    required this.index,
    required super.sprite,
    required super.size,
    required super.position,
    required this.correctPosition,
    this.artwork,
    Vector2? renderBleed,
  }) : renderBleed = renderBleed ?? Vector2.zero() {
    // Board zoom draws sprites below 1:1; the default FilterQuality.none
    // aliases their antialiased rims into a visible light edge on device.
    paint.filterQuality = FilterQuality.medium;
    paint.isAntiAlias = true;
  }

  /// Canonical piece number (row * columns + column); save files reference it.
  final int index;

  /// How far the shaped sprite extends past this piece's base rectangle.
  /// Position, snapping, saves and touch areas all use the base rectangle;
  /// only the drawing is bigger, shifted up-left by this much. (The base
  /// rect also stays the touch target on purpose: it is a steadier, more
  /// finger-friendly area than the exact knobby outline.)
  final Vector2 renderBleed;
  final PieceArtwork? artwork;

  static const _lockedPriority = -1;
  static const _loosePriority = 0;
  static const _draggingPriority = 100;

  /// World position of this piece's top-left corner when solved.
  final Vector2 correctPosition;

  bool _isLocked = false;

  // Coordinates and saved locks commit on drop. The live count and visual
  // lock flag wait for the entire chunk's animation to finish.
  bool _isSnapping = false;
  int? _activePointerId;
  Vector2 _settleOffset = Vector2.zero();
  double _settleTime = 0;
  VoidCallback? _onSettled;
  static const _settleDuration = 0.1;

  bool get isLocked => _isLocked;
  bool get isSettling => _isSnapping;

  // The tray-return check follows the finger, not the piece's center: a
  // piece grabbed by its edge can hang over the tray while the finger is
  // still on the board. Null while the piece is not being carried.
  Vector2? _dragPointerOnScreen;

  /// Records where the finger carrying this piece is on screen. The tray
  /// drives lifted pieces without this component's own drag callbacks, so
  /// it reports the pointer through this hook too.
  void noteDragPointer(Vector2 canvasPosition) {
    _dragPointerOnScreen = canvasPosition.clone();
  }

  /// Returns and clears the carried pointer's screen position; the game
  /// reads it once when resolving a drop.
  Vector2? takeDragPointer() {
    final pointer = _dragPointerOnScreen;
    _dragPointerOnScreen = null;
    return pointer;
  }

  /// Dragged or glide-settling pieces ride above everything else — the
  /// game's tray overlay re-renders them so they stay visible when the
  /// finger crosses the (nearly opaque) tray.
  bool get isElevated => priority == _draggingPriority;

  void setDragging(bool dragging) {
    priority = dragging ? _draggingPriority : _loosePriority;
  }

  /// Visual offset of the glide-settle animation. The game's shadow layer
  /// applies the same offset, so the shadow travels with the artwork.
  Vector2 get glideOffset {
    if (!_isSnapping) {
      return Vector2.zero();
    }
    final t = (_settleTime / _settleDuration).clamp(0.0, 1.0);
    return _settleOffset * (1 - Curves.easeOut.transform(t));
  }

  /// The sprite box this piece draws into, around its base rectangle.
  Rect get _spriteBounds => Rect.fromLTWH(
    -renderBleed.x,
    -renderBleed.y,
    sprite!.srcSize.x,
    sprite!.srcSize.y,
  );

  // The shaped image is drawn 1:1 around the base rectangle instead of being
  // squeezed into it. overridePaint keeps opacity and flash effects working.
  // Deliberately NOT calling super.render: it would draw the sprite a second
  // time, squeezed into the base rect.
  //
  // Resting and locked pieces blit the baked decorated sprite (cheap, and
  // the component paint covers the whole piece). Only elevated pieces
  // re-render live from the photo, so the outline stays crisp while carried
  // under camera zoom; their drop shadow is drawn by the game's shadow
  // layer, below every dragged body.
  @override
  // ignore: must_call_super
  void render(Canvas canvas) {
    canvas.save();
    final glide = glideOffset;
    canvas.translate(glide.x, glide.y);
    final pieceArtwork = artwork;
    if (isElevated && pieceArtwork != null) {
      pieceArtwork.render(
        canvas,
        bounds: _spriteBounds,
        decorationScale: 1 / game.camera.viewfinder.zoom,
        photoPaint: paint,
      );
    } else {
      sprite!.render(
        canvas,
        position: -renderBleed,
        size: sprite!.srcSize,
        overridePaint: paint,
      );
    }
    canvas.restore();
  }

  /// This piece's lifted drop shadow, in local coordinates. Called by the
  /// game's shadow layers so every shadow lands below every dragged body —
  /// a dragged chunk must never shade its own members.
  void renderDropShadow(Canvas canvas) {
    final pieceArtwork = artwork;
    if (pieceArtwork == null) {
      return;
    }
    canvas.save();
    final glide = glideOffset;
    canvas.translate(glide.x, glide.y);
    pieceArtwork.renderShadow(
      canvas,
      bounds: _spriteBounds,
      decorationScale: 1 / game.camera.viewfinder.zoom,
      lifted: true,
    );
    canvas.restore();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_onSettled != null) {
      _settleTime += dt;
      if (_settleTime >= _settleDuration) {
        final callback = _onSettled!;
        _onSettled = null;
        callback();
      }
    }
  }

  // Locked and snapping pieces let drag gestures pass through to the board.
  @override
  bool containsLocalPoint(Vector2 point) {
    if (_isLocked || _isSnapping) {
      return false;
    }

    return super.containsLocalPoint(point);
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (_activePointerId == null && game.beginPieceDrag(this)) {
      _activePointerId = event.pointerId;
      noteDragPointer(event.canvasPosition);
    }
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (event.pointerId != _activePointerId || _isLocked || _isSnapping) {
      return;
    }

    // Canvas positions stay valid when the pointer moves outside the piece.
    // In Flame 1.38, canvasStartPosition is the current pointer position;
    // the end adds the delta. Recorded even while a pinch suppresses
    // movement below: the release's tray-return decision must follow the
    // real finger, not its pre-pinch position.
    noteDragPointer(event.canvasStartPosition);
    if (game.isScaling) {
      return;
    }

    // With an unrotated camera, dividing by zoom converts to world distance.
    final screenDelta = event.canvasEndPosition - event.canvasStartPosition;
    final worldDelta = screenDelta / game.camera.viewfinder.zoom;
    game.movePieceBy(this, worldDelta);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);

    if (event.pointerId == _activePointerId) {
      _activePointerId = null;
      settle(allowTrayReturn: !dragWasCancelled);
    }
  }

  /// Resolves a drop from either a board drag or a tray drag.
  void settle({bool allowTrayReturn = true}) {
    game.settlePiece(this, allowTrayReturn: allowTrayReturn);
  }

  /// Restores a saved locked piece: no snap animation, no progress count.
  void restoreAsLocked() {
    _isLocked = true;
    position.setFrom(correctPosition);
    priority = _lockedPriority;
  }

  /// Animate the artwork, never the base cell's canonical/save coordinates.
  void animateSettle(Vector2 target, {required VoidCallback onComplete}) {
    _isSnapping = true;
    _settleOffset = position - target;
    position.setFrom(target);
    _settleTime = 0;
    _onSettled = onComplete;
    priority = _draggingPriority;
  }

  void finishSettle({required bool locked}) {
    _isSnapping = false;
    _isLocked = locked;
    priority = locked ? _lockedPriority : _loosePriority;
    add(
      ColorEffect(
        Colors.white,
        EffectController(duration: 0.12, alternate: true),
        opacityTo: locked ? 0.5 : 0.2,
      ),
    );
  }
}
