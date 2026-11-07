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

/// Whether a strip-local slot at [left] with [width] overlaps the tray's
/// visible window ([scrollOffset] to [scrollOffset] + [viewWidth]). The tray
/// culls offscreen thumbnails with this, so it must match the strip layout:
/// strip x == -scrollOffset, clipped to the tray's own bounds.
bool trayColumnVisible({
  required double left,
  required double width,
  required double scrollOffset,
  required double viewWidth,
}) {
  return left + width >= scrollOffset && left <= scrollOffset + viewWidth;
}

// Tray geometry. Thumbnails show the full sprite box (base cell plus the
// transparent tab margins), and slots advance by that whole box — so pieces
// can never overlap. Density comes from sizing thumbnails to always fit
// [trayVisibleColumns] columns across the tray (2026-11-05 phone rulings:
// ~12 pieces visible, zero overlap).
const trayRows = 2;
const trayVisibleColumns = 6;
const trayPadding = 10.0;
const traySlotGap = 4.0;

/// Thumbnail (sprite box) height inside a tray of the given size: bounded
/// by the row height, and by the width needed to fit the visible columns.
double trayThumbnailHeight(double width, double height, double spriteAspect) {
  final heightDriven = (height - trayPadding * (trayRows + 1)) / trayRows;
  final widthDriven =
      ((width - trayPadding) / trayVisibleColumns - traySlotGap) / spriteAspect;
  return min(heightDriven, widthDriven);
}

/// The tray height at which both constraints above agree — any taller just
/// adds empty background below the rows. Callers still cap it.
double preferredTrayHeight(double width, double spriteAspect) {
  final widthDriven =
      ((width - trayPadding) / trayVisibleColumns - traySlotGap) / spriteAspect;
  return trayRows * widthDriven + trayPadding * (trayRows + 1);
}

/// Camera zoom limits, relative to the zoom that fits the whole board:
/// never below the fitted view (the board always fills the screen), in to 4x.
double clampZoom(double zoom, double fitZoom) {
  return zoom.clamp(fitZoom, fitZoom * 4.0).toDouble();
}

/// Whether the camera is meaningfully zoomed in past the fitted view.
/// Within 1% of the fit zoom counts as fitted: panning stays disabled and
/// the camera snaps home. The tolerance absorbs rounding from cumulative
/// pinch scale factors, which rarely land exactly on the fit zoom.
bool isZoomedBeyondFit(double zoom, double fitZoom) {
  return zoom > fitZoom * 1.01;
}
