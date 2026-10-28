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
import 'package:flutter/services.dart';

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

  // Set while the snap glide runs: touches are already disabled, but the
  // piece only counts — and saves — as locked once it reaches its spot.
  // Otherwise a save written mid-glide could claim a finished board before
  // the completion record exists.
  bool _isSnapping = false;

  bool get isLocked => _isLocked;

  // The shaped image is drawn 1:1 around the base rectangle instead of being
  // squeezed into it. overridePaint keeps opacity and flash effects working.
  // Deliberately NOT calling super.render: it would draw the sprite a second
  // time, squeezed into the base rect.
  @override
  // ignore: must_call_super
  void render(Canvas canvas) {
    sprite!.render(
      canvas,
      position: -renderBleed,
      size: sprite!.srcSize,
      overridePaint: paint,
    );
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
    priority = _draggingPriority;
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (_isLocked || _isSnapping || game.isScaling) {
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

    if (!_isLocked && !_isSnapping) {
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
      game.sounds?.playDrop();
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
    _isSnapping = true;
    add(
      MoveToEffect(
        correctPosition.clone(),
        EffectController(duration: 0.1, curve: Curves.easeOut),
        onComplete: _onSnapComplete,
      ),
    );
  }

  void _onSnapComplete() {
    _isSnapping = false;
    _isLocked = true;
    // A small physical "click" when a piece locks, with a matching sound.
    // Errors are ignored: not every device (or test) supports haptics.
    game.sounds?.playSnap();
    HapticFeedback.lightImpact().ignore();
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
