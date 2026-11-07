// "Next puzzle" on the gallery wall: picking the category's next unfinished
// painting, and chaining straight into it at the same size.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/game_screen.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_completion.dart';
import 'package:jigsaw_puzzle/puzzle_launcher.dart';

import 'test_helpers.dart';

/// A sibling of [singlePieceImage] in the same fixture category.
const secondTestImage = PuzzleImage(
  id: 'test-b',
  title: 'Second test puzzle',
  categoryId: 'test',
  fileName: 'test_photo.jpg',
);

const testCatalog = [singlePieceImage, secondTestImage];

void main() {
  group('nextPuzzleAfter', () {
    const images = [
      PuzzleImage(id: 'a1', title: 'A1', categoryId: 'a', fileName: 'x.jpg'),
      PuzzleImage(id: 'a2', title: 'A2', categoryId: 'a', fileName: 'x.jpg'),
      PuzzleImage(id: 'b1', title: 'B1', categoryId: 'b', fileName: 'x.jpg'),
      PuzzleImage(id: 'a3', title: 'A3', categoryId: 'a', fileName: 'x.jpg'),
    ];

    PuzzleImage image(String id) => images.firstWhere((i) => i.id == id);

    test('offers the next image of the same category', () {
      expect(nextPuzzleAfter(image('a1'), {}, catalog: images), image('a2'));
      // a3 follows a2 in category order even with b1 between them.
      expect(nextPuzzleAfter(image('a2'), {}, catalog: images), image('a3'));
    });

    test('wraps around the end of the category', () {
      expect(nextPuzzleAfter(image('a3'), {}, catalog: images), image('a1'));
    });

    test('skips completed images', () {
      expect(
        nextPuzzleAfter(image('a1'), {'a2'}, catalog: images),
        image('a3'),
      );
    });

    test('is null when the rest of the category is completed', () {
      expect(
        nextPuzzleAfter(image('a1'), {'a2', 'a3'}, catalog: images),
        isNull,
      );
    });

    test('is null when the category has no other image', () {
      expect(nextPuzzleAfter(image('b1'), {}, catalog: images), isNull);
    });

    test('reads the real catalog by default', () {
      final landscapes = imagesInCategory('landscapes');
      expect(nextPuzzleAfter(landscapes.first, {}), landscapes[1]);
    });
  });

  group('gallery wall', () {
    late MockSharedPreferences prefs;

    setUp(() {
      prefs = MockSharedPreferences()..install();
      prefs.storage[singlePieceProgressKey] = singleLoosePieceSave()
          .toJsonString();
    });

    String completionKeyFor(PuzzleImage image, PuzzleSize size) =>
        'flutter.${puzzleCompletionKey(imageId: image.id, columns: size.columns, rows: size.rows)}';

    testWidgets('the Next puzzle button pops with the chosen painting', (
      tester,
    ) async {
      PuzzleImage? popResult;
      var popped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  popResult = await Navigator.push<PuzzleImage>(
                    context,
                    MaterialPageRoute<PuzzleImage>(
                      builder: (_) => GameScreen(
                        image: singlePieceImage,
                        size: singlePieceSize,
                        catalog: testCatalog,
                      ),
                    ),
                  );
                  popped = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      late JigsawGame game;
      await tester.runAsync(() async {
        // Fixed pumps: with a warm image cache the game loads instantly and
        // its ticker keeps scheduling frames, so pumpAndSettle cannot settle.
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        game = currentGame(tester);
        await game.loaded;
      });
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await completePuzzle(tester, game);

      // The chain action leads; the exit is the quiet secondary button.
      expect(find.widgetWithText(FilledButton, 'Next puzzle'), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, 'Back to the gallery'),
        findsOneWidget,
      );

      await tester.tap(find.text('Next puzzle'));
      await tester.pumpAndSettle();
      expect(popped, isTrue);
      expect(popResult?.id, secondTestImage.id);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the launcher chains into the popped painting, no size sheet', (
      tester,
    ) async {
      var flowDone = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  await startPuzzleFlow(
                    context,
                    singlePieceImage,
                    catalog: testCatalog,
                  );
                  flowDone = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('24 pieces'));
      await tester.runAsync(() async {
        // Fixed pumps: with a warm image cache the game loads instantly and
        // its ticker keeps scheduling frames, so pumpAndSettle cannot settle.
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await currentGame(tester).loaded;
      });
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        tester.widget<GameScreen>(find.byType(GameScreen)).image.id,
        singlePieceImage.id,
      );

      // Pop with a painting, exactly as the completion card's button does.
      Navigator.of(
        tester.element(find.byType(GameScreen)),
      ).pop(secondTestImage);
      await tester.runAsync(() async {
        // Fixed pumps: pumpAndSettle never settles against a running Flame
        // ticker, and the chained game starts loading immediately.
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await currentGame(tester).loaded;
      });
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final chained = tester.widget<GameScreen>(find.byType(GameScreen));
      expect(chained.image.id, secondTestImage.id);
      expect(find.text('24 pieces'), findsNothing); // straight in, no sheet
      expect(flowDone, isFalse, reason: 'The flow ends at the real exit.');

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(flowDone, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('hides the offer when the rest of the category is done', (
      tester,
    ) async {
      prefs.storage[completionKeyFor(secondTestImage, singlePieceSize)] =
          CompletionRecord(
            count: 1,
            lastCompletedAt: DateTime.utc(2026),
          ).toJsonString();
      final game = await bootGameScreen(
        tester,
        image: singlePieceImage,
        size: singlePieceSize,
        catalog: testCatalog,
      );
      await completePuzzle(tester, game);

      expect(find.text('Next puzzle'), findsNothing);
      // With no chain to offer, the exit is promoted back to the hero button.
      expect(
        find.widgetWithText(FilledButton, 'Back to the gallery'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a completion at another size does not hide the offer', (
      tester,
    ) async {
      prefs.storage[completionKeyFor(
            secondTestImage,
            const PuzzleSize(columns: 2, rows: 2),
          )] =
          CompletionRecord(
            count: 1,
            lastCompletedAt: DateTime.utc(2026),
          ).toJsonString();
      final game = await bootGameScreen(
        tester,
        image: singlePieceImage,
        size: singlePieceSize,
        catalog: testCatalog,
      );
      await completePuzzle(tester, game);

      expect(find.widgetWithText(FilledButton, 'Next puzzle'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
