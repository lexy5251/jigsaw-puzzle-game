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
      // Wide tray, uncapped: the row height binds — (180 - 30) / 2.
      expect(trayThumbnailHeight(800, 180, 1, maxThumbnailHeight: null), 75);
      // Same tray with the shipped ceiling: phone-size pieces win.
      expect(trayThumbnailHeight(800, 180, 1), trayThumbnailHeightCap);
      // Narrow tray: the five-column rule binds — (390 / 5) - 4.
      expect(trayThumbnailHeight(400, 400, 1), 74);
    });

    test('preferred height is exactly what the two rows need', () {
      final height = preferredTrayHeight(400, 1);
      expect(height, 2 * 74 + 30);
      expect(trayThumbnailHeight(400, height, 1), closeTo(74, 1e-9));
    });

    test('a thumbnail ceiling bounds wide screens only', () {
      // 1180-wide: the five-column rule would allow 230, the rows 185 —
      // the ceiling wins and the preferred height follows it.
      expect(trayThumbnailHeight(1180, 400, 1, maxThumbnailHeight: 74), 74);
      expect(preferredTrayHeight(1180, 1, maxThumbnailHeight: 74), 2 * 74 + 30);
      // Narrow screens under the ceiling keep their width-driven size.
      expect(trayThumbnailHeight(320, 400, 1, maxThumbnailHeight: 74), 58);
    });
  });

  group('trayHeightCap', () {
    test('falls back to the legacy cap before the image is loaded', () {
      // min(30% of 844, 200) with no board aspect to measure slack against.
      expect(trayHeightCap(screenWidth: 390, screenHeight: 844), 200);
    });

    test('keeps the legacy cap when the board is height-bound', () {
      // Landscape: a 3:2 board already fills the height; no slack to take.
      expect(
        trayHeightCap(screenWidth: 844, screenHeight: 390, boardAspect: 2 / 3),
        closeTo(117, 1e-9),
      );
    });

    test('absorbs the slack a width-bound square board leaves', () {
      // 390x700 portrait, square board: the board needs 390 * 0.92 / 0.85
      // of height; everything below is the tray's to take.
      expect(
        trayHeightCap(screenWidth: 390, screenHeight: 700, boardAspect: 1),
        closeTo(700 - 390 * 0.92 / 0.85, 1e-9),
      );
    });

    test('never exceeds 45% of the screen even with more slack', () {
      // The owner's phone: slack is ~422 px, but the guard stops at 45%.
      expect(
        trayHeightCap(screenWidth: 390, screenHeight: 844, boardAspect: 1),
        closeTo(844 * 0.45, 1e-9),
      );
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
