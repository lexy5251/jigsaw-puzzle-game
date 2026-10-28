import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/puzzle_logic.dart';

void main() {
  group('shouldSnap', () {
    const pieceWidth = 100.0; // tolerance = 40 px

    test('snaps when the piece is close to its spot', () {
      expect(shouldSnap(Vector2(30, 20), Vector2.zero(), pieceWidth), isTrue);
    });

    test('does not snap when the piece is too far', () {
      expect(shouldSnap(Vector2(50, 50), Vector2.zero(), pieceWidth), isFalse);
    });

    test('measures straight-line distance, not per-axis', () {
      // 39 px on each axis is ~55 px diagonally — outside the 40 px radius.
      expect(shouldSnap(Vector2(39, 39), Vector2.zero(), pieceWidth), isFalse);
    });

    test('exactly at the threshold does not snap', () {
      expect(shouldSnap(Vector2(40, 0), Vector2.zero(), pieceWidth), isFalse);
    });
  });

  group('PuzzleProgress', () {
    test('completes only after every piece locks', () {
      final progress = PuzzleProgress(totalPieces: 3);
      expect(progress.lockPiece(), isFalse);
      expect(progress.lockPiece(), isFalse);
      expect(progress.isComplete, isFalse);
      expect(progress.lockPiece(), isTrue);
      expect(progress.isComplete, isTrue);
      expect(progress.lockedCount, 3);
    });
  });

  group('isEdgePiece', () {
    // 4x3 grid: indexes 0-3 top row, 8-11 bottom row, 4/7 side pieces,
    // 5 and 6 are the only interior pieces.
    const columns = 4;
    const rows = 3;

    test('corners and borders are edges', () {
      for (final index in [0, 1, 2, 3, 4, 7, 8, 9, 10, 11]) {
        expect(isEdgePiece(index, columns, rows), isTrue, reason: '$index');
      }
    });

    test('interior pieces are not edges', () {
      expect(isEdgePiece(5, columns, rows), isFalse);
      expect(isEdgePiece(6, columns, rows), isFalse);
    });

    test('every piece is an edge in a single-row puzzle', () {
      for (var index = 0; index < 5; index++) {
        expect(isEdgePiece(index, 5, 1), isTrue, reason: '$index');
      }
    });
  });

  group('clampTrayScroll', () {
    test('never scrolls when all pieces fit in the tray', () {
      expect(clampTrayScroll(50, 200, 400), 0);
      expect(clampTrayScroll(-50, 200, 400), 0);
    });

    test('stops at the end of the strip', () {
      // 1000 px of pieces in a 400 px tray -> at most 600 px of scroll.
      expect(clampTrayScroll(9999, 1000, 400), 600);
      expect(clampTrayScroll(-10, 1000, 400), 0);
      expect(clampTrayScroll(300, 1000, 400), 300);
    });
  });

  group('clampZoom', () {
    test('limits zoom to 0.5x-4x of the fit zoom', () {
      const fit = 2.0;
      expect(clampZoom(0.1, fit), 1.0);
      expect(clampZoom(100, fit), 8.0);
      expect(clampZoom(3, fit), 3.0);
    });
  });
}
