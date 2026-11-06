import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/piece_tray.dart';
import 'package:jigsaw_puzzle/puzzle_piece.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';

/// Returning pieces to the tray (2026-11-05 phone request): a lone loose
/// piece dropped over the tray leaves the board and rejoins the strip,
/// while chunks and locked pieces stay on the board.
void main() {
  const key = 'return-tests';
  const width = 1600 / 6;
  const height = 1067 / 4;
  Vector2 home(int index) => Vector2(index % 6 * width, index ~/ 6 * height);
  final offset = Vector2(300, 220);

  Future<JigsawGame> boot(
    WidgetTester tester,
    InMemorySaveStore store, {
    required Map<int, Vector2> loose,
  }) async {
    await store.save(
      key,
      PuzzleSaveState(
        trayPieceIndexes: [
          for (var i = 0; i < 24; i++)
            if (!loose.containsKey(i)) i,
        ],
        lockedPieceIndexes: const [],
        loosePiecePositions: loose,
      ),
    );
    final game = JigsawGame(
      imageAsset: 'test_photo.jpg',
      columns: 6,
      rows: 4,
      saveStore: store,
      saveKey: key,
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

  Map<int, PuzzlePiece> pieces(JigsawGame game) => {
    for (final piece in game.world.children.whereType<PuzzlePiece>())
      piece.index: piece,
  };

  double trayTopOf(JigsawGame game) =>
      game.camera.viewport.children.whereType<PieceTray>().single.position.y;

  /// Releases [piece] with its center resting mid-tray on screen.
  Future<void> dropOnTray(
    WidgetTester tester,
    JigsawGame game,
    PuzzlePiece piece,
  ) async {
    final onTray = Vector2(game.size.x / 2, game.size.y - 20);
    game.movePieceTo(piece, game.camera.globalToLocal(onTray) - piece.size / 2);
    piece.settle();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('a lone piece dropped on the tray returns to it', (tester) async {
    final store = InMemorySaveStore();
    final game = await boot(tester, store, loose: {8: home(8) + offset});
    expect(game.trayPieceIndexes, hasLength(23));

    await dropOnTray(tester, game, pieces(game)[8]!);

    expect(pieces(game), isEmpty);
    expect(game.trayPieceIndexes, hasLength(24));

    // It must reappear where it was dropped — on-screen, not at the far
    // (possibly scrolled-off) end of the strip. The 800-wide tray shows
    // 10 columns x 2 rows, and the strip is unscrolled.
    final slot = game.visibleTrayPieceIndexes.indexOf(8);
    expect(slot, isNonNegative);
    expect(slot, lessThan(20));

    // The save reflects the return, so a reload cannot resurrect the piece.
    await game.progressSaved;
    final saved = await store.load(key);
    expect(saved!.loosePiecePositions, isEmpty);
    expect(saved.trayPieceIndexes, contains(8));
  });

  testWidgets('a returned piece hides under the active edges-only filter', (
    tester,
  ) async {
    final store = InMemorySaveStore();
    // Piece 8 is an interior piece on a 6x4 board.
    final game = await boot(tester, store, loose: {8: home(8) + offset});
    game.setEdgesOnlyFilter(true);

    await dropOnTray(tester, game, pieces(game)[8]!);

    expect(game.trayPieceIndexes, contains(8));
    expect(game.visibleTrayPieceIndexes, isNot(contains(8)));
  });

  testWidgets('a joined chunk dropped on the tray stays on the board', (
    tester,
  ) async {
    final store = InMemorySaveStore();
    // Identical offsets put 0 and 1 at their exact relative positions, so
    // the restore rebuilds them as one chunk.
    final game = await boot(
      tester,
      store,
      loose: {0: home(0) + offset, 1: home(1) + offset},
    );

    await dropOnTray(tester, game, pieces(game)[0]!);

    expect(pieces(game), hasLength(2));
    expect(game.trayPieceIndexes, hasLength(22));
    // The normal drop rules ran instead: the chunk was pushed clear of the
    // tray, so no part of it hides underneath.
    for (final piece in pieces(game).values) {
      final bottomOnScreen = game.camera.localToGlobal(
        piece.position + piece.size,
      );
      expect(bottomOnScreen.y, lessThan(trayTopOf(game)));
    }
  });
}
