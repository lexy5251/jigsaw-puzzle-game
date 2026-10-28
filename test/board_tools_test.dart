import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/puzzle_logic.dart';
import 'package:jigsaw_puzzle/puzzle_piece.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';

/// Covers the two board helper toggles: the edges-only tray filter and the
/// ghost image preview. Both can be flipped before the game finishes loading
/// (the buttons exist immediately), so that path is tested too.
void main() {
  Future<JigsawGame> bootGame(
    WidgetTester tester, {
    void Function(JigsawGame game)? beforeLoad,
    JigsawGame? puzzle,
  }) async {
    final game =
        puzzle ?? JigsawGame(imageAsset: 'test_photo.jpg', columns: 6, rows: 4);
    beforeLoad?.call(game);
    await tester.runAsync(() async {
      await tester.pumpWidget(GameWidget(game: game));
      await game.loaded;
    });
    // A few real ticks so queued component additions (tray, ghost) mount.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return game;
  }

  testWidgets('edges-only filter hides interior pieces, keeps them in play', (
    tester,
  ) async {
    final game = await bootGame(tester);
    expect(game.visibleTrayPieceIndexes.length, 24);

    game.setEdgesOnlyFilter(true);
    await tester.pump(const Duration(milliseconds: 16));

    // 6x4 grid: 24 pieces total, 2x4 = 8 interior, 16 edge pieces.
    expect(game.visibleTrayPieceIndexes.length, 16);
    expect(
      game.visibleTrayPieceIndexes.every((i) => isEdgePiece(i, 6, 4)),
      isTrue,
    );
    // The filter only hides pieces; all 24 still belong to the tray (saves
    // must keep listing them).
    expect(game.trayPieceIndexes.length, 24);

    game.setEdgesOnlyFilter(false);
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.visibleTrayPieceIndexes.length, 24);
  });

  testWidgets('ghost preview toggles between invisible and faint', (
    tester,
  ) async {
    final game = await bootGame(tester);
    expect(game.ghostPreviewOpacity, 0);

    game.setGhostPreview(true);
    expect(game.ghostPreviewOpacity, greaterThan(0));
    expect(game.ghostPreviewOpacity, lessThan(0.5)); // faint, not a spoiler

    game.setGhostPreview(false);
    expect(game.ghostPreviewOpacity, 0);
  });

  for (final cancel in [false, true]) {
    testWidgets(
      'filter waits for a tray drag to ${cancel ? 'cancel' : 'finish'}',
      (tester) async {
        final store = InMemorySaveStore();
        await store.save(
          'filter-drag',
          PuzzleSaveState(
            trayPieceIndexes: List.generate(24, (i) => i),
            lockedPieceIndexes: const [],
            loosePiecePositions: const {},
          ),
        );
        final game = await bootGame(
          tester,
          puzzle: JigsawGame(
            imageAsset: 'test_photo.jpg',
            columns: 6,
            rows: 4,
            saveStore: store,
            saveKey: 'filter-drag',
          ),
        );
        final gesture = await tester.startGesture(const Offset(50, 550));
        await gesture.moveTo(const Offset(75, 550));
        await tester.pump(const Duration(milliseconds: 16));

        // Another finger can toggle the toolbar while the first holds a piece.
        game.setEdgesOnlyFilter(true);
        game.setEdgesOnlyFilter(false);
        game.setEdgesOnlyFilter(true);
        await tester.pump(const Duration(milliseconds: 16));
        expect(game.visibleTrayPieceIndexes.length, 24);

        if (cancel) {
          await gesture.cancel();
        } else {
          for (var i = 1; i <= 8; i++) {
            await gesture.moveTo(Offset(75, 550 - 150 * i / 8));
            await tester.pump(const Duration(milliseconds: 16));
          }
          await gesture.up();
        }
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        expect(game.visibleTrayPieceIndexes.length, cancel ? 16 : 15);
        expect(
          game.visibleTrayPieceIndexes.every((i) => isEdgePiece(i, 6, 4)),
          isTrue,
        );
        expect(game.trayPieceIndexes.length, cancel ? 24 : 23);
        if (!cancel) {
          expect(game.world.children.whereType<PuzzlePiece>().single.index, 0);
          expect(game.visibleTrayPieceIndexes, isNot(contains(0)));
          expect(game.trayPieceIndexes, isNot(contains(0)));
          await game.progressSaved;
          expect(
            (await store.load('filter-drag'))!.isConsistentFor(24),
            isTrue,
          );
        }
      },
    );
  }

  testWidgets('toggles flipped before loading apply once the board is ready', (
    tester,
  ) async {
    final game = await bootGame(
      tester,
      beforeLoad: (game) {
        game.setGhostPreview(true);
        game.setEdgesOnlyFilter(true);
      },
    );

    expect(game.ghostPreviewOpacity, greaterThan(0));
    expect(game.visibleTrayPieceIndexes.length, 16);
  });
}
