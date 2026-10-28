import 'dart:math';

import 'package:flame/components.dart';

/// Pure gameplay rules, kept free of Flame component state so they can be
/// unit-tested without building a game (see test/puzzle_logic_test.dart).

/// How close a piece must be to its correct spot to snap, as a fraction of
/// the piece's width. Forgiving on purpose.
const snapToleranceFraction = 0.4;

/// Whether a piece released at [position] should snap onto [correctPosition].
bool shouldSnap(Vector2 position, Vector2 correctPosition, double pieceWidth) {
  return position.distanceTo(correctPosition) <
      pieceWidth * snapToleranceFraction;
}

/// Counts locked pieces and reports when the puzzle is done.
class PuzzleProgress {
  PuzzleProgress({required this.totalPieces});

  final int totalPieces;
  int _lockedCount = 0;

  int get lockedCount => _lockedCount;
  bool get isComplete => _lockedCount == totalPieces;

  /// Registers one locked piece; returns true when this completes the puzzle.
  bool lockPiece() {
    assert(_lockedCount < totalPieces, 'more pieces locked than exist');
    _lockedCount++;
    return isComplete;
  }
}

/// Whether the piece at [index] belongs to the puzzle's outermost ring.
/// Edge pieces form the frame players usually assemble first.
bool isEdgePiece(int index, int columns, int rows) {
  final row = index ~/ columns;
  final column = index % columns;
  return row == 0 || row == rows - 1 || column == 0 || column == columns - 1;
}

/// Clamps a tray scroll offset so the piece strip never scrolls past its ends.
double clampTrayScroll(double offset, double stripWidth, double trayWidth) {
  final maxOffset = max(0.0, stripWidth - trayWidth);
  return offset.clamp(0.0, maxOffset).toDouble();
}

/// Camera zoom limits, relative to the zoom that fits the whole board:
/// out to half the board's size, in to 4x.
double clampZoom(double zoom, double fitZoom) {
  return zoom.clamp(fitZoom * 0.5, fitZoom * 4.0).toDouble();
}
