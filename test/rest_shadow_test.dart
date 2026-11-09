// Resting (unplaced) board pieces cast a small contact shadow so they read
// as paper lying on the board instead of printed onto it. Locked pieces sit
// flush in the picture (no shadow), and an elevated piece hands off to the
// stronger lifted drag shadow. These tests pin that handoff through the
// game's rest-shadow hook instead of scraping pixels.

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/puzzle_piece.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';

void main() {
  const columns = 6;
  const rows = 4;
  const width = 1600 / columns;
  const height = 1067 / rows;

  /// Boots a 6x4 game with piece 8 loose mid-board, piece 3 locked, and the
  /// rest in the tray.
  Future<JigsawGame> boot(WidgetTester tester) async {
    const key = 'rest-shadow';
    final store = InMemorySaveStore();
    await store.save(
      key,
      PuzzleSaveState(
        trayPieceIndexes: [
          for (var i = 0; i < columns * rows; i++)
            if (i != 8 && i != 3) i,
        ],
        lockedPieceIndexes: const [3],
        loosePiecePositions: {8: Vector2(2 * width, 1.5 * height)},
      ),
    );
    final game = JigsawGame(
      imageAsset: 'test_photo.jpg',
      columns: columns,
      rows: rows,
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

  PuzzlePiece pieceOf(JigsawGame game, int index) => game.world.children
      .whereType<PuzzlePiece>()
      .singleWhere((piece) => piece.index == index);

  testWidgets('resting pieces cast the contact shadow; locked sit flush', (
    tester,
  ) async {
    final game = await boot(tester);
    expect(game.restShadowPieceIndexes, [8]);

    // The shadow layer sits between locked bodies and loose bodies: a loose
    // piece visibly rests ON the flush picture, while a joined chunk's
    // internal shadows stay hidden under its own members.
    final shadowLayers = game.world.children.where(
      (child) => child.priority == -1,
    );
    expect(shadowLayers, hasLength(1));
    expect(pieceOf(game, 3).priority, lessThan(-1));
    expect(pieceOf(game, 8).priority, greaterThan(-1));
  });

  testWidgets('dragging and locking both hand the shadow off', (tester) async {
    final game = await boot(tester);
    final piece = pieceOf(game, 8);

    expect(game.beginPieceDrag(piece), isTrue);
    expect(
      game.restShadowPieceIndexes,
      isEmpty,
      reason: 'An elevated piece shows the lifted drag shadow instead.',
    );

    // Drop exactly on the solved spot: the piece locks after the settle
    // glide and must stay shadowless, flush in the picture.
    game.movePieceTo(piece, piece.correctPosition.clone());
    piece.settle();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(piece.isLocked, isTrue);
    expect(game.restShadowPieceIndexes, isEmpty);
  });
}
