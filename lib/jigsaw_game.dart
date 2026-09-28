import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

/// How many columns and rows the photo is sliced into (6 x 4 = 24 pieces).
const _columns = 6;
const _rows = 4;

class JigsawGame extends FlameGame {
  final _random = Random();

  @override
  Color backgroundColor() => const Color(0xFF2E3440);

  @override
  Future<void> onLoad() async {
    final image = await images.load('test_photo.jpg');

    // Size of one piece within the original photo, in image pixels.
    final srcPieceSize = Vector2(
      image.width / _columns,
      image.height / _rows,
    );

    // Scale so the assembled photo would cover ~80% of the screen,
    // preserving its aspect ratio.
    final scale = min(
      size.x * 0.8 / image.width,
      size.y * 0.8 / image.height,
    );
    final pieceSize = srcPieceSize * scale;

    for (var row = 0; row < _rows; row++) {
      for (var col = 0; col < _columns; col++) {
        // Each piece is not a separate image — it's a viewport (srcPosition +
        // srcSize) into the one shared photo. No pixel copying needed.
        final sprite = Sprite(
          image,
          srcPosition: Vector2(col * srcPieceSize.x, row * srcPieceSize.y),
          srcSize: srcPieceSize,
        );
        add(SpriteComponent(
          sprite: sprite,
          size: pieceSize,
          position: _randomPositionWithin(size, pieceSize),
        ));
      }
    }
  }

  /// A random position where a piece of [pieceSize] stays fully on screen.
  Vector2 _randomPositionWithin(Vector2 bounds, Vector2 pieceSize) {
    return Vector2(
      _random.nextDouble() * (bounds.x - pieceSize.x),
      _random.nextDouble() * (bounds.y - pieceSize.y),
    );
  }
}
