// Piece logic overview:
// Gestures delegate to the game's chunk model; this component owns only its
// shaped drawing, base-cell hit target, and visual settle feedback.
//
// All piece positions use board (world) coordinates.

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

import 'jigsaw_game.dart';

/// A board piece that can be dragged until it snaps into its correct position.
class PuzzlePiece extends SpriteComponent
    with DragCallbacks, HasGameReference<JigsawGame> {
  PuzzlePiece({
    required this.index,
    required super.sprite,
    required super.size,
    required super.position,
    required this.correctPosition,
    Vector2? renderBleed,
  }) : renderBleed = renderBleed ?? Vector2.zero();

  /// Canonical piece number (row * columns + column); save files reference it.
  final int index;

  /// How far the shaped sprite extends past this piece's base rectangle.
  /// Position, snapping, saves and touch areas all use the base rectangle;
  /// only the drawing is bigger, shifted up-left by this much. (The base
  /// rect also stays the touch target on purpose: it is a steadier, more
  /// finger-friendly area than the exact knobby outline.)
  final Vector2 renderBleed;

  static const _lockedPriority = -1;
  static const _loosePriority = 0;
  static const _draggingPriority = 100;

  /// World position of this piece's top-left corner when solved.
  final Vector2 correctPosition;

  bool _isLocked = false;

  // Coordinates are exact throughout the visual glide. Counting/saving as
  // locked waits for the entire chunk's animation to finish.
  bool _isSnapping = false;
  int? _activePointerId;
  Vector2 _settleOffset = Vector2.zero();
  double _settleTime = 0;
  VoidCallback? _onSettled;
  static const _settleDuration = 0.1;

  bool get isLocked => _isLocked;
  bool get isSettling => _isSnapping;

  void setDragging(bool dragging) {
    priority = dragging ? _draggingPriority : _loosePriority;
  }

  // The shaped image is drawn 1:1 around the base rectangle instead of being
  // squeezed into it. overridePaint keeps opacity and flash effects working.
  // Deliberately NOT calling super.render: it would draw the sprite a second
  // time, squeezed into the base rect.
  @override
  // ignore: must_call_super
  void render(Canvas canvas) {
    canvas.save();
    if (_isSnapping) {
      final t = (_settleTime / _settleDuration).clamp(0.0, 1.0);
      final remaining = 1 - Curves.easeOut.transform(t);
      canvas.translate(
        _settleOffset.x * remaining,
        _settleOffset.y * remaining,
      );
    }
    sprite!.render(
      canvas,
      position: -renderBleed,
      size: sprite!.srcSize,
      overridePaint: paint,
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
    }
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (event.pointerId != _activePointerId ||
        _isLocked ||
        _isSnapping ||
        game.isScaling) {
      return;
    }

    // Canvas positions stay valid when the pointer moves outside the piece.
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
      settle();
    }
  }

  /// Resolves a drop from either a board drag or a tray drag.
  void settle() {
    game.settlePiece(this);
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
