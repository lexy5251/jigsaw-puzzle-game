import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/puzzle_piece.dart';

/// End-to-end checks of the drag → drop → snap pipeline using simulated
/// touch gestures, covering the tray lift and the lock-on-release behavior.
///
/// Regression guard: Flame's DragUpdateEvent.canvasEndPosition is one move
/// delta AHEAD of the finger, which once made carried pieces overshoot the
/// drop point and miss the snap window (see PieceTray.onDragUpdate).
void main() {
  // Test surface is 800x600, so the tray (18% of height, max 130) is 108 tall
  // and starts at y=492. The first tray thumbnail sits around x=10..98.
  const trayThumbTouch = Offset(50, 550);
  const liftedTouch = Offset(50, 400); // above the tray: piece is on the board

  Future<JigsawGame> bootGame(WidgetTester tester) async {
    final game = JigsawGame(imageAsset: 'test_photo.jpg', columns: 6, rows: 4);
    // runAsync lets the real asset load + image decode inside onLoad finish
    // (they happen off the fake test clock).
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

  /// Drags a piece out of the tray and returns it (still held by the gesture).
  Future<(TestGesture, PuzzlePiece)> liftPieceFromTray(
    WidgetTester tester,
    JigsawGame game,
  ) async {
    final gesture = await tester.startGesture(trayThumbTouch);
    await tester.pump(const Duration(milliseconds: 16));
    await dragTo(tester, gesture, trayThumbTouch, liftedTouch);
    final piece = game.world.children.whereType<PuzzlePiece>().single;
    return (gesture, piece);
  }

  testWidgets('dragging empty board pans the camera',
      (tester) async {
    final game = await bootGame(tester);
    final cameraBefore = game.camera.viewfinder.position.clone();
    final gesture = await tester.startGesture(const Offset(400, 100));
    await tester.pump(const Duration(milliseconds: 16));
    await dragTo(
        tester, gesture, const Offset(400, 100), const Offset(300, 100));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.camera.viewfinder.position.distanceTo(cameraBefore),
        greaterThan(0.01));
  });

  /// Canvas point that puts the carried piece's center on [worldTarget].
  Offset canvasPointFor(JigsawGame game, Vector2 worldTarget) {
    final canvas = game.camera.localToGlobal(worldTarget);
    return Offset(canvas.x, canvas.y);
  }

  testWidgets('piece dropped on its correct spot locks and snaps exactly',
      (tester) async {
    final game = await bootGame(tester);
    final (gesture, piece) = await liftPieceFromTray(tester, game);

    final target = piece.correctPosition + piece.size / 2;
    await dragTo(tester, gesture, liftedTouch, canvasPointFor(game, target));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));

    // Give the snap glide (100ms) and flash time to run.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(piece.isLocked, isTrue);
    expect(piece.position.distanceTo(piece.correctPosition), lessThan(0.01));
    expect(game.progress.lockedCount, 1);
  });

  testWidgets('piece dropped a full piece-width away stays loose',
      (tester) async {
    final game = await bootGame(tester);
    final (gesture, piece) = await liftPieceFromTray(tester, game);

    final target =
        piece.correctPosition + piece.size / 2 + Vector2(piece.size.x, 0);
    await dragTo(tester, gesture, liftedTouch, canvasPointFor(game, target));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));

    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(piece.isLocked, isFalse);
    expect(game.progress.lockedCount, 0);
  });
}
