// Piece logic overview:
// 1. Drag a loose piece around the board, accounting for camera zoom.
// 2. On release, check whether it is close enough to its correct position.
// 3. If close, disable dragging and animate it into place. Otherwise, leave
//    it loose and keep it clear of the tray.
// 4. After snapping, flash the piece and tell the game to count it as locked.
//
// All piece positions use board (world) coordinates.

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

import 'jigsaw_game.dart';
import 'puzzle_logic.dart';

/// A board piece that can be dragged until it snaps into its correct position.
class PuzzlePiece extends SpriteComponent
    with DragCallbacks, HasGameReference<JigsawGame> {
  PuzzlePiece({
    required this.index,
    required super.sprite,
    required super.size,
    required super.position,
    required this.correctPosition,
  });

  /// Canonical piece number (row * columns + column); save files reference it.
  final int index;

  static const _lockedPriority = -1;
  static const _loosePriority = 0;
  static const _draggingPriority = 100;

  /// World position of this piece's top-left corner when solved.
  final Vector2 correctPosition;

  bool _isLocked = false;

  bool get isLocked => _isLocked;

  // Locked pieces let drag gestures pass through to the board.
  @override
  bool containsLocalPoint(Vector2 point) {
    if (_isLocked) {
      return false;
    }

    return super.containsLocalPoint(point);
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    priority = _draggingPriority;
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (_isLocked || game.isScaling) {
      return;
    }

    // Canvas positions stay valid when the pointer moves outside the piece.
    // With an unrotated camera, dividing by zoom converts to world distance.
    final screenDelta = event.canvasEndPosition - event.canvasStartPosition;
    final worldDelta = screenDelta / game.camera.viewfinder.zoom;
    position += worldDelta;
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);

    if (!_isLocked) {
      settle();
    }
  }

  /// Resolves a drop from either a board drag or a tray drag.
  void settle() {
    final isNearCorrectPosition = shouldSnap(position, correctPosition, size.x);

    if (isNearCorrectPosition) {
      _snapIntoPlace();
    } else {
      priority = _loosePriority;
      game.keepPieceClearOfTray(this);
      game.persistProgress(); // the snap path saves via onPieceLocked
    }
  }

  /// Restores a saved locked piece: no snap animation, no progress count.
  void restoreAsLocked() {
    _isLocked = true;
    position.setFrom(correctPosition);
    priority = _lockedPriority;
  }

  void _snapIntoPlace() {
    // Disable touches immediately, while the piece is still moving into place.
    _isLocked = true;
    add(
      MoveToEffect(
        correctPosition.clone(),
        EffectController(duration: 0.1, curve: Curves.easeOut),
        onComplete: _onSnapComplete,
      ),
    );
  }

  void _onSnapComplete() {
    priority = _lockedPriority;
    add(
      ColorEffect(
        Colors.white,
        EffectController(duration: 0.12, alternate: true),
        opacityTo: 0.5,
      ),
    );

    // Count the piece only after it reaches its correct position.
    game.onPieceLocked();
  }
}
