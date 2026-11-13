import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/piece_tray.dart';
import 'package:jigsaw_puzzle/puzzle_logic.dart';
import 'package:jigsaw_puzzle/puzzle_piece.dart';

/// Two-row tray from the 2026-11-05 phone-test rulings (#2): more pieces
/// visible at once, columns filling top-to-bottom, horizontal scroll kept.
void main() {
  // Test surface is 800x600: the phone-size piece ceiling (74) binds under
  // the 75 the row height would allow, so the two rows need exactly 178 —
  // just below trayHeightCap's 180 — and the tray spans y=422..600.
  Future<JigsawGame> bootGame(
    WidgetTester tester, {
    int columns = 6,
    int rows = 4,
    double? trayMaxThumbnailHeight = trayThumbnailHeightCap,
  }) async {
    final game = JigsawGame(
      imageAsset: 'test_photo.jpg',
      columns: columns,
      rows: rows,
      trayMaxThumbnailHeight: trayMaxThumbnailHeight,
    );
    // runAsync lets the real asset load + image decode inside onLoad finish.
    await tester.runAsync(() async {
      await tester.pumpWidget(GameWidget(game: game));
      await game.loaded;
    });
    // A few real ticks so queued component additions (tray, board) mount.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return game;
  }

  PieceTray trayOf(JigsawGame game) =>
      game.camera.viewport.children.whereType<PieceTray>().single;

  /// Moves a held gesture in small steps, pumping between them, so gesture
  /// recognizers see a realistic stream of pointer events.
  Future<void> dragTo(
    WidgetTester tester,
    TestGesture gesture,
    Offset from,
    Offset to,
  ) async {
    const steps = 8;
    for (var i = 1; i <= steps; i++) {
      await gesture.moveTo(from + (to - from) * (i / steps));
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<PuzzlePiece> liftFrom(
    WidgetTester tester,
    JigsawGame game,
    Offset trayTouch,
  ) async {
    final gesture = await tester.startGesture(trayTouch);
    await tester.pump(const Duration(milliseconds: 16));
    await dragTo(tester, gesture, trayTouch, const Offset(50, 350));
    final piece = game.world.children.whereType<PuzzlePiece>().single;
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
    return piece;
  }

  testWidgets('thumbnails fill two rows, column by column', (tester) async {
    final game = await bootGame(tester);
    final tray = trayOf(game);
    expect(tray.size.y, 178);

    final positions = tray.thumbnailPositions;
    // Second thumbnail sits below the first; third starts the next column.
    expect(positions[1].x, positions[0].x);
    expect(positions[1].y, greaterThan(positions[0].y));
    expect(positions[2].y, positions[0].y);
    expect(positions[2].x, greaterThan(positions[0].x));
  });

  testWidgets('a top-row touch lifts the column\'s first piece', (
    tester,
  ) async {
    final game = await bootGame(tester);
    final order = game.trayPieceIndexes;
    final piece = await liftFrom(tester, game, const Offset(50, 460));
    expect(piece.index, order[0]);
  });

  testWidgets('a bottom-row touch lifts the column\'s second piece', (
    tester,
  ) async {
    final game = await bootGame(tester);
    final order = game.trayPieceIndexes;
    final piece = await liftFrom(tester, game, const Offset(50, 550));
    expect(piece.index, order[1]);
  });

  // The row gap spans y=506..516, so its midpoint is y=511.
  for (final (touchY, expectedRow) in [(508.0, 0), (512.0, 1)]) {
    testWidgets('a gap touch at y=$touchY lifts the nearest row', (
      tester,
    ) async {
      final game = await bootGame(tester);
      final order = game.trayPieceIndexes;
      final piece = await liftFrom(tester, game, Offset(50, touchY));
      expect(piece.index, order[expectedRow]);
    });
  }

  testWidgets('horizontal drag scrolls the strip and clamps at its end', (
    tester,
  ) async {
    // 54 pieces in 2 rows = 27 columns: the strip overflows the 800-wide
    // tray, so scrolling must stop exactly at the strip's end.
    final game = await bootGame(tester, columns: 9, rows: 6);
    final tray = trayOf(game);
    final positions = tray.thumbnailPositions;

    final slotWidth = positions[2].x - positions[0].x;
    final maxScroll = positions[0].x + 27 * slotWidth - 800;
    expect(maxScroll, greaterThan(0));

    // Several long swipes scroll well past the strip's end: the offset must
    // clamp there, not overshoot.
    for (var swipe = 0; swipe < 3; swipe++) {
      final gesture = await tester.startGesture(const Offset(600, 550));
      await tester.pump(const Duration(milliseconds: 16));
      await dragTo(
        tester,
        gesture,
        const Offset(600, 550),
        const Offset(50, 550),
      );
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(tray.scrollOffset, closeTo(maxScroll, 0.001));
  });

  testWidgets('a phone-width tray fits five full columns with no overlap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final game = await bootGame(tester);
    final tray = trayOf(game);
    final positions = tray.thumbnailPositions;
    final slotWidth = positions[2].x - positions[0].x;

    // Slots advance by the full sprite box plus a gap: overlap impossible.
    expect(slotWidth, greaterThanOrEqualTo(tray.thumbnailSize.x));
    // Five columns (10 pieces) sit fully inside the 400-wide tray...
    expect(positions[8].x + tray.thumbnailSize.x, lessThanOrEqualTo(400));
    // ...and a sixth full column would NOT fit — the density really is five.
    // (Under the rejected 6-column geometry this sum is 396, inside 400.)
    expect(positions[10].x + tray.thumbnailSize.x, greaterThan(400));
  });

  testWidgets('a tall narrow surface lets the tray grow past the legacy cap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Uncapped pieces: the shipped phone-size ceiling would keep the rows
    // at 178 and never reach the cap this test exists to exercise.
    final game = await bootGame(tester, trayMaxThumbnailHeight: null);
    final tray = trayOf(game);
    // The 3:2 board is width-bound here with ~620px of slack below it, so
    // the cap no longer clamps to the legacy 200 and the tray takes its
    // preferred height (~338). This pins the slack branch end to end: a
    // flipped board aspect in the game's cap wiring would fall back to 200.
    final srcSize = tray.spriteSrcSizeFor(game.trayPieceIndexes.first)!;
    expect(
      tray.size.y,
      closeTo(
        preferredTrayHeight(
          800,
          srcSize.x / srcSize.y,
          maxThumbnailHeight: null,
        ),
        0.001,
      ),
    );
    expect(tray.size.y, greaterThan(300));
  });
}
