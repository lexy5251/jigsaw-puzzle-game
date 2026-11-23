// "Next puzzle" on the gallery wall: picking the category's next unfinished
// painting, and chaining straight into it at the same size.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/game_screen.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';

import 'test_helpers.dart';

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

    testWidgets('the Next puzzle button pops with the chosen painting', (
      tester,
    ) async {
      final route = await pushGameScreen(
        tester,
        image: singlePieceImage,
        size: singlePieceSize,
        catalogs: const PuzzleCatalogs(gallery: chainTestCatalog),
      );
      await completePuzzle(tester, currentGame(tester));

      // The chain action leads; the exit is the quiet secondary button.
      expect(find.widgetWithText(FilledButton, 'Next puzzle'), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, 'Back to gallery'),
        findsOneWidget,
      );

      await tester.tap(find.text('Next puzzle'));
      await tester.pumpAndSettle();
      expect(route.popped, isTrue);
      expect(route.popResult?.id, secondTestImage.id);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the launcher chains into the popped painting, no size sheet', (
      tester,
    ) async {
      final flow = await launchPuzzleFlowToSheet(
        tester,
        image: singlePieceImage,
        catalogs: const PuzzleCatalogs(gallery: chainTestCatalog),
      );
      await tester.tap(find.bySemanticsIdentifier('puzzle-start'));
      await tester.runAsync(() => settleLaunchedGame(tester));
      expect(
        tester.widget<GameScreen>(find.byType(GameScreen)).image.id,
        singlePieceImage.id,
      );

      // Pop with a painting, exactly as the completion card's button does.
      Navigator.of(
        tester.element(find.byType(GameScreen)),
      ).pop(secondTestImage);
      // The chained game starts loading immediately — same settle dance.
      await tester.runAsync(() => settleLaunchedGame(tester));
      final chained = tester.widget<GameScreen>(find.byType(GameScreen));
      expect(chained.image.id, secondTestImage.id);
      // Straight into the chained game — no size sheet in between.
      expect(find.bySemanticsIdentifier('puzzle-start'), findsNothing);
      expect(flow.done, isFalse, reason: 'The flow ends at the real exit.');

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(flow.done, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('hides the offer when the rest of the category is done', (
      tester,
    ) async {
      prefs.storage[completionKeyFor(secondTestImage)] = completionOn(
        DateTime.utc(2026),
      ).toJsonString();
      final game = await bootGameScreen(
        tester,
        image: singlePieceImage,
        size: singlePieceSize,
        catalogs: const PuzzleCatalogs(gallery: chainTestCatalog),
      );
      await completePuzzle(tester, game);

      expect(find.text('Next puzzle'), findsNothing);
      // With no chain to offer, the exit is promoted back to the hero button.
      expect(
        find.widgetWithText(FilledButton, 'Back to gallery'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a completion at another size does not hide the offer', (
      tester,
    ) async {
      prefs.storage[completionKeyFor(secondTestImage, columns: 2, rows: 2)] =
          completionOn(DateTime.utc(2026)).toJsonString();
      final game = await bootGameScreen(
        tester,
        image: singlePieceImage,
        size: singlePieceSize,
        catalogs: const PuzzleCatalogs(gallery: chainTestCatalog),
      );
      await completePuzzle(tester, game);

      expect(find.widgetWithText(FilledButton, 'Next puzzle'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('story chain', () {
    late MockSharedPreferences prefs;

    setUp(() {
      prefs = MockSharedPreferences()..install();
      prefs.storage[saveKeyFor(sceneImageOne)] = singleLoosePieceSave()
          .toJsonString();
    });

    testWidgets('finishing a scene offers the newly unlocked next one', (
      tester,
    ) async {
      // The default gallery catalog holds no 'story' images, so the offer
      // proves the walk switched to the story list.
      final route = await pushGameScreen(
        tester,
        image: sceneImageOne,
        size: singlePieceSize,
        catalogs: const PuzzleCatalogs(story: sceneFixtures),
      );
      await completePuzzle(tester, currentGame(tester));

      await tester.tap(find.widgetWithText(FilledButton, 'Next puzzle'));
      await tester.pumpAndSettle();
      expect(route.popResult?.id, sceneImageTwo.id);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a replay skips read scenes and offers the open one', (
      tester,
    ) async {
      // Scenes 1 and 2 are read; re-reading scene 1 offers scene 3 —
      // exactly the scene the prefix rule has open, never a locked one.
      prefs.storage[completionKeyFor(sceneImageOne)] = completionOn(
        DateTime.utc(2026),
      ).toJsonString();
      prefs.storage[completionKeyFor(sceneImageTwo)] = completionOn(
        DateTime.utc(2026),
      ).toJsonString();
      final route = await pushGameScreen(
        tester,
        image: sceneImageOne,
        size: singlePieceSize,
        catalogs: const PuzzleCatalogs(story: sceneFixtures),
      );
      await completePuzzle(tester, currentGame(tester));

      await tester.tap(find.widgetWithText(FilledButton, 'Next puzzle'));
      await tester.pumpAndSettle();
      expect(route.popResult?.id, sceneImageThree.id);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a replay at a NEW size still offers the open scene', (
      tester,
    ) async {
      // Scenes unlock by ANY-size finishes: scenes 1 and 2 were read at
      // 5x5, so re-reading scene 1 at 1x1 must point at open scene 3 —
      // not re-offer scene 2 just because 1x1 never finished it.
      prefs.storage[completionKeyFor(sceneImageOne, columns: 5, rows: 5)] =
          completionOn(DateTime.utc(2026)).toJsonString();
      prefs.storage[completionKeyFor(sceneImageTwo, columns: 5, rows: 5)] =
          completionOn(DateTime.utc(2026)).toJsonString();
      final route = await pushGameScreen(
        tester,
        image: sceneImageOne,
        size: singlePieceSize,
        catalogs: const PuzzleCatalogs(story: sceneFixtures),
      );
      await completePuzzle(tester, currentGame(tester));

      await tester.tap(find.widgetWithText(FilledButton, 'Next puzzle'));
      await tester.pumpAndSettle();
      expect(route.popResult?.id, sceneImageThree.id);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('gapped records offer the open scene, never a locked one', (
      tester,
    ) async {
      // Scene 1 and scene 3 are on record but scene 2 is not — impossible
      // through the app, conceivable in storage (a failed write mid-chain).
      // A skip-completed walk from scene 3 would offer still-wrapped scene
      // 4; the shared prefix gate must point back at open scene 2 instead.
      const sceneImageFour = PuzzleImage(
        id: 'scene-4',
        title: 'Scene Four',
        categoryId: storyCategoryId,
        fileName: 'test_photo.jpg',
      );
      prefs.storage[completionKeyFor(sceneImageOne)] = completionOn(
        DateTime.utc(2026),
      ).toJsonString();
      prefs.storage[completionKeyFor(sceneImageThree)] = completionOn(
        DateTime.utc(2026),
      ).toJsonString();
      prefs.storage[saveKeyFor(sceneImageThree)] = singleLoosePieceSave()
          .toJsonString();
      final route = await pushGameScreen(
        tester,
        image: sceneImageThree,
        size: singlePieceSize,
        catalogs: const PuzzleCatalogs(story: [...sceneFixtures, sceneImageFour]),
      );
      await completePuzzle(tester, currentGame(tester));

      await tester.tap(find.widgetWithText(FilledButton, 'Next puzzle'));
      await tester.pumpAndSettle();
      expect(route.popResult?.id, sceneImageTwo.id);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a fully read story ends the run', (tester) async {
      // Every scene read (at any size): a replay must not circle back to
      // scene 1 — the exit is the hero button again.
      for (final scene in sceneFixtures) {
        prefs.storage[completionKeyFor(scene, columns: 5, rows: 5)] =
            completionOn(DateTime.utc(2026)).toJsonString();
      }
      final game = await bootGameScreen(
        tester,
        image: sceneImageOne,
        size: singlePieceSize,
        catalogs: const PuzzleCatalogs(story: sceneFixtures),
      );
      await completePuzzle(tester, game);

      expect(find.text('Next puzzle'), findsNothing);
      // With no chain to offer, the exit is the hero button — and a scene's
      // exit names the Story tab it actually returns to.
      expect(
        find.widgetWithText(FilledButton, 'Back to the story'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a scene finish records completion but no daily credit', (
      tester,
    ) async {
      // The daily check reads the gallery catalog, where scenes never
      // appear — the reason the story list must not ride in `catalog`.
      final game = await bootGameScreen(
        tester,
        image: sceneImageOne,
        size: singlePieceSize,
        catalogs: const PuzzleCatalogs(story: sceneFixtures),
      );
      await completePuzzle(tester, game);

      expect(prefs.storage, contains(completionKeyFor(sceneImageOne)));
      expect(prefs.storage.keys, isNot(contains('flutter.daily.days')));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
