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

  group('tray geometry', () {
    test('thumbnail height is bounded by rows and by visible columns', () {
      // Wide tray: the row height binds — (180 - 30) / 2.
      expect(trayThumbnailHeight(800, 180, 1), 75);
      // Narrow tray: the six-column rule binds — (390 / 6) - 4.
      expect(trayThumbnailHeight(400, 400, 1), 61);
    });

    test('preferred height is exactly what the two rows need', () {
      final height = preferredTrayHeight(400, 1);
      expect(height, 2 * 61 + 30);
      expect(trayThumbnailHeight(400, height, 1), closeTo(61, 1e-9));
    });
  });

  group('clampZoom', () {
    test('limits zoom to fit-4x of the fit zoom', () {
      const fit = 2.0;
      // Zooming out never goes below the fitted view.
      expect(clampZoom(0.1, fit), 2.0);
      expect(clampZoom(100, fit), 8.0);
      expect(clampZoom(3, fit), 3.0);
    });
  });

  group('isZoomedBeyondFit', () {
    test('treats anything within 1% of the fit zoom as fitted', () {
      const fit = 2.0;
      expect(isZoomedBeyondFit(fit, fit), isFalse);
      expect(isZoomedBeyondFit(fit * 1.005, fit), isFalse);
      expect(isZoomedBeyondFit(fit * 0.9, fit), isFalse);
      expect(isZoomedBeyondFit(fit * 1.02, fit), isTrue);
    });
  });

  group('trayColumnVisible', () {
    // Window: scrolled 100 to the right, 400 wide -> visible span 100..500.
    const scroll = 100.0;
    const view = 400.0;

    test('keeps slots overlapping the window, drops the rest', () {
      bool visible(double left) => trayColumnVisible(
        left: left,
        width: 50,
        scrollOffset: scroll,
        viewWidth: view,
      );
      expect(visible(200), isTrue); // fully inside
      expect(visible(80), isTrue); // straddles the left edge
      expect(visible(480), isTrue); // straddles the right edge
      expect(visible(20), isFalse); // fully left of the window
      expect(visible(520), isFalse); // fully right of the window
    });

    test('a slot touching the window edge still draws', () {
      // A culled-but-visible slot would blank a thumbnail mid-scroll, so the
      // boundary cases must count as visible.
      expect(
        trayColumnVisible(
          left: 50,
          width: 50,
          scrollOffset: scroll,
          viewWidth: view,
        ),
        isTrue,
      );
      expect(
        trayColumnVisible(
          left: 500,
          width: 50,
          scrollOffset: scroll,
          viewWidth: view,
        ),
        isTrue,
      );
    });
  });
}
