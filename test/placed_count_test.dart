import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_piece.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';

import 'test_helpers.dart';

void main() {
  // Includes an isolated piece, multiple accepted drops, and the final drop
  // that must also retry completion recording after an interrupted glide.
  for (final placed in [1, 2, 24]) {
    testWidgets('$placed accepted placements survive an interrupted snap', (
      tester,
    ) async {
      final prefs = MockSharedPreferences()..install();
      const size = PuzzleSize(columns: 6, rows: 4);
      final key =
          'flutter.${puzzleSaveKey(imageId: singlePieceImage.id, columns: 6, rows: 4)}';
      prefs.storage[key] = PuzzleSaveState(
        trayPieceIndexes: [for (var i = placed; i < 24; i++) i],
        lockedPieceIndexes: const [],
        loosePiecePositions: {
          for (var i = 0; i < placed; i++) i: Vector2(300, 220),
        },
      ).toJsonString();
      final game = await bootGameScreen(
        tester,
        image: singlePieceImage,
        size: size,
      );
      final pieces = game.world.children.whereType<PuzzlePiece>().toList();
      for (final piece in pieces) {
        game.movePieceTo(piece, piece.correctPosition + Vector2(20, 5));
        piece.settle();
        expect(piece.isSettling, isTrue);
      }
      // No animation ticks before leaving. Live visuals still have count 0.
      expect(game.placedCount.value, 0);
      await tester.runAsync(() => game.progressSaved);
      final saved = PuzzleSaveState.fromJsonString(
        prefs.storage[key] as String,
      )!;
      expect(saved.isConsistentFor(24), isTrue);
      expect(saved.lockedPieceIndexes, hasLength(placed));
      await tester.pumpWidget(const SizedBox.shrink());

      final resumed = await bootGameScreen(
        tester,
        image: singlePieceImage,
        size: size,
      );
      expect(resumed.placedCount.value, placed);
      expect(resumed.progress.lockedCount, placed);
      expect(find.text('$placed / 24'), findsOneWidget);
      final restored = resumed.world.children.whereType<PuzzlePiece>();
      expect(restored, hasLength(placed));
      for (final piece in restored) {
        expect(piece.isLocked, isTrue);
        expect(piece.position, piece.correctPosition);
      }
      if (placed == 24) {
        await tester.runAsync(() => resumed.completionFinished);
        expect(resumed.progress.isComplete, isTrue);
        expect(prefs.storage.containsKey(key), isFalse);
        expect(prefs.storage.containsKey('flutter.done.test.6x4'), isTrue);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
