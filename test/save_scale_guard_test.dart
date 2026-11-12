import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';

import 'test_helpers.dart';

/// Saves store world positions in image pixels, so a snapshot written against
/// a different image resolution (e.g. before the 3072px photo swap) must start
/// fresh instead of restoring pieces at the wrong scale: loose pieces would
/// pile into one corner and joined groups would silently dissolve.
void main() {
  const key = 'save.test-photo.6x4';

  Future<bool> bootAndReportResumed(
    WidgetTester tester,
    InMemorySaveStore store,
  ) async {
    bool? resumed;
    final game = JigsawGame(
      imageAsset: 'test_photo.jpg',
      columns: 6,
      rows: 4,
      saveStore: store,
      saveKey: key,
      onBoardLoaded: (value) => resumed = value,
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(GameWidget(game: game));
      await game.loaded;
      await game.progressSaved;
    });
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return resumed!;
  }

  PuzzleSaveState saveWith({int? boardWidth}) => PuzzleSaveState(
    trayPieceIndexes: [for (var i = 1; i < 24; i++) i],
    lockedPieceIndexes: const [],
    loosePiecePositions: {0: Vector2(100, 80)},
    boardWidth: boardWidth,
  );

  testWidgets('a save stamped with the image width resumes', (tester) async {
    final store = InMemorySaveStore();
    await store.save(key, saveWith(boardWidth: testPhotoWidth));

    expect(await bootAndReportResumed(tester, store), isTrue);
  });

  testWidgets('a save without a width stamp starts fresh', (tester) async {
    // The shape of every save written before the field existed.
    final store = InMemorySaveStore();
    await store.save(key, saveWith());

    expect(await bootAndReportResumed(tester, store), isFalse);
  });

  testWidgets('a save from a different image width starts fresh', (
    tester,
  ) async {
    final store = InMemorySaveStore();
    await store.save(key, saveWith(boardWidth: testPhotoWidth * 2));

    expect(await bootAndReportResumed(tester, store), isFalse);
  });
}
