import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/game_screen.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/main.dart';

/// Covers the select → size picker → game screen navigation flow.
void main() {
  testWidgets('selecting an image and size opens the game screen', (
    tester,
  ) async {
    await tester.pumpWidget(const JigsawPuzzleApp());

    expect(find.text('Landscapes'), findsOneWidget);

    await tester.tap(find.text('Alpine Lakes Panorama'));
    await tester.pumpAndSettle();

    expect(find.text('24 pieces · Easy'), findsOneWidget);
    expect(find.text('60 pieces · Medium'), findsOneWidget);
    expect(find.text('120 pieces · Hard'), findsOneWidget);

    await tester.tap(find.text('24 pieces · Easy'));
    // runAsync lets the real photo load + decode finish while the sheet-close
    // and route animations play. pumpAndSettle would hang here: Flame's game
    // loop keeps scheduling frames forever once the GameWidget mounts.
    await tester.runAsync(() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      final game = tester
          .widget<GameWidget<JigsawGame>>(find.byType(GameWidget<JigsawGame>))
          .game!;
      await game.loaded;
    });
    await tester.pump();

    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('Test Photo · 24 pieces'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(GameScreen), findsNothing);
    expect(find.text('Alpine Lakes Panorama'), findsOneWidget);
  });

  testWidgets('size picker scrolls in a short window', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const JigsawPuzzleApp());
    await tester.tap(find.byType(Card).first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final hardOption = find.text('120 pieces · Hard');
    await tester.scrollUntilVisible(
      hardOption,
      80,
      scrollable: find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(hardOption.hitTestable(), findsOneWidget);
  });
}
