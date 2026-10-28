import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/game_sounds.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/puzzle_piece.dart';

/// Counts cue calls instead of playing audio.
class _FakeSounds implements GameSounds {
  int drops = 0;
  int snaps = 0;
  int completes = 0;
  int disposals = 0;

  @override
  Future<void> preload() async {}

  @override
  void playDrop() => drops++;

  @override
  void playSnap() => snaps++;

  @override
  void playComplete() => completes++;

  @override
  Future<void> dispose() async => disposals++;
}

void main() {
  const trayThumbTouch = Offset(50, 550);
  const liftedTouch = Offset(50, 400);

  Future<JigsawGame> bootGame(WidgetTester tester, GameSounds sounds) async {
    // Two pieces: finishing the puzzle stays cheap in a gesture-driven test.
    final game = JigsawGame(
      imageAsset: 'test_photo.jpg',
      columns: 2,
      rows: 1,
      sounds: sounds,
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(GameWidget(game: game));
      await game.loaded;
    });
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return game;
  }

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

  Offset canvasPointFor(JigsawGame game, Vector2 worldTarget) {
    final canvas = game.camera.localToGlobal(worldTarget);
    return Offset(canvas.x, canvas.y);
  }

  /// Lifts the first tray piece and releases it at [worldTarget] (its
  /// center), letting the snap/flash animations finish.
  Future<PuzzlePiece> liftAndDropAt(
    WidgetTester tester,
    JigsawGame game,
    Vector2 Function(PuzzlePiece piece) worldTarget,
  ) async {
    final gesture = await tester.startGesture(trayThumbTouch);
    await tester.pump(const Duration(milliseconds: 16));
    await dragTo(tester, gesture, trayThumbTouch, liftedTouch);
    final piece = game.world.children.whereType<PuzzlePiece>().firstWhere(
      (candidate) => !candidate.isLocked,
    );
    await dragTo(
      tester,
      gesture,
      liftedTouch,
      canvasPointFor(game, worldTarget(piece)),
    );
    await gesture.up();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return piece;
  }

  testWidgets('drop, snap and completion each play their cue', (tester) async {
    final sounds = _FakeSounds();
    final game = await bootGame(tester, sounds);

    // 1. Drop the first piece a full piece-width from home: a loose drop.
    final first = await liftAndDropAt(
      tester,
      game,
      (piece) =>
          piece.correctPosition + piece.size / 2 + Vector2(0, piece.size.y),
    );
    expect(first.isLocked, isFalse);
    expect(sounds.drops, 1);
    expect(sounds.snaps, 0);

    // 2. Drag it from the board onto its spot: a snap, no completion yet.
    final pieceCenter = canvasPointFor(game, first.position + first.size / 2);
    final gesture = await tester.startGesture(pieceCenter);
    await tester.pump(const Duration(milliseconds: 16));
    await dragTo(
      tester,
      gesture,
      pieceCenter,
      canvasPointFor(game, first.correctPosition + first.size / 2),
    );
    await gesture.up();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(first.isLocked, isTrue);
    expect(sounds.snaps, 1);
    expect(sounds.completes, 0);

    // 3. The second piece straight onto its spot: snap + completion chime.
    final second = await liftAndDropAt(
      tester,
      game,
      (piece) => piece.correctPosition + piece.size / 2,
    );
    expect(second.isLocked, isTrue);
    expect(sounds.snaps, 2);
    expect(sounds.completes, 1);
    expect(sounds.drops, 1); // unchanged: snapping is not a loose drop

    await tester.pumpWidget(const SizedBox.shrink());
    expect(sounds.disposals, 1);
  });
}
