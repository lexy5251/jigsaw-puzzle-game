import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';

void main() {
  testWidgets('game boots with an empty board and a full tray', (tester) async {
    final game = JigsawGame(imageAsset: 'test_photo.jpg', columns: 6, rows: 4);
    // runAsync lets the real asset load + image decode inside onLoad finish
    // (they happen off the fake test clock).
    await tester.runAsync(() async {
      await tester.pumpWidget(GameWidget(game: game));
      await game.loaded;
    });
    await tester.pump();

    expect(game.progress.totalPieces, 24);
    expect(game.progress.lockedCount, 0);
    expect(game.progress.isComplete, isFalse);
  });
}
