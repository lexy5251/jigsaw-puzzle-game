// Dev tool, not a test: renders the REAL size sheet — the 2026-11-13
// redesign (framed painting, size rows with word statuses, one launch
// button) — over its category page in every status state, so the owner
// judges the look as an image before a device build. Skipped unless
// SIZE_SHEET_PREVIEW=1:
//   SIZE_SHEET_PREVIEW=1 flutter test test/size_sheet_preview_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_completion.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';
import 'package:jigsaw_puzzle/puzzle_select_screen.dart';
import 'package:jigsaw_puzzle/studio_surfaces.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  final enabled = previewEnabled('SIZE_SHEET_PREVIEW');

  testWidgets('render the size sheet states and the replay flow', (
    tester,
  ) async {
    final landscapes = imagesInCategory('landscapes');
    final image = landscapes.first;

    String completionKeyFor(PuzzleSize size) => puzzleCompletionKey(
      imageId: image.id,
      columns: size.columns,
      rows: size.rows,
    );

    // A run mid-way on a size that was ALSO finished before — per the
    // owner's precedence rule its row must read "In progress" (one word,
    // never both) — plus a plain finished smallest size.
    final mixedSeed = {
      puzzleSaveKey(imageId: image.id, columns: 10, rows: 10):
          partiallyPlacedSave(
            100,
            placed: 57,
            startedDay: '2026-11-11',
          ).toJsonString(),
      completionKeyFor(puzzleSizes[0]): completionJson(DateTime(2026, 11, 9)),
      completionKeyFor(puzzleSizes[1]): completionJson(DateTime(2026, 11, 10)),
    };
    // Every size finished: every row reads "Completed" and the button says
    // "Play again".
    final finishedSeed = {
      for (final size in puzzleSizes)
        completionKeyFor(size): completionJson(DateTime(2026, 11, 10)),
    };

    await tester.runAsync(() async {
      // Real fonts and glyphs, so the owner judges the actual studio type.
      await loadStudioFonts();
      await loadMaterialIcons();

      // One shared recipe from seeded prefs to the open sheet — the
      // captures must all show what the app really does, so there is
      // exactly one copy of the navigation to drift.
      Future<GlobalKey> openSheet(
        Map<String, Object> seed, {
        Size size = const Size(390, 844),
      }) async {
        SharedPreferences.setMockInitialValues(seed);
        final boundaryKey = GlobalKey();
        await pumpPhoneApp(
          tester,
          PuzzleSelectScreen(clock: previewNow),
          size: size,
          boundaryKey: boundaryKey,
        );
        await tester.pumpAndSettle();

        final categoryCard = find.bySemanticsIdentifier('category-landscapes');
        await scrollSelectScreenTo(tester, categoryCard, delta: 150);
        await tester.tap(categoryCard);
        await tester.pumpAndSettle();

        // Warm the one cache entry both the backdrop grid and the sheet's
        // framed preview resolve, so neither paints gray in the capture.
        await precachePreviewImages(
          tester.element(find.byType(GridView)),
          [for (final painting in landscapes) painting.assetPath],
          width: TiltedPhotoCard.thumbnailCacheWidth,
        );
        await tester.pump();

        final card = catalogPuzzleCard(image.id);
        await scrollSelectScreenTo(tester, card, delta: 150);
        await tester.tap(card);
        await tester.pumpAndSettle();
        return boundaryKey;
      }

      Future<void> render(
        String state,
        Map<String, Object> seed,
        double width,
        double height,
        String sizeName,
      ) async {
        final boundaryKey = await openSheet(seed, size: Size(width, height));
        await capturePreviewPng(
          boundaryKey,
          'docs/size-sheet-preview-$state-$sizeName.png',
        );
      }

      await render('fresh', {}, 390, 844, 'phone-390');
      // The busiest state at both judging sizes; the rest at phone width.
      for (final (width, height, sizeName) in previewPhoneSizes) {
        await render('mixed', mixedSeed, width, height, sizeName);
      }
      await render('finished', finishedSeed, 390, 844, 'phone-390');

      // The replay flow, step by step: tap the Completed row (button flips
      // to Play again), then launch — a fresh board, no dialog in between.
      {
        final boundaryKey = await openSheet(mixedSeed);
        await tester.tap(
          find.bySemanticsIdentifier('puzzle-size-${image.id}-5x5'),
        );
        await tester.pumpAndSettle();
        await capturePreviewPng(
          boundaryKey,
          'docs/size-sheet-preview-replay-selected-phone-390.png',
        );

        await tester.tap(find.bySemanticsIdentifier('puzzle-start'));
        await settleLaunchedGame(tester);
        await capturePreviewPng(
          boundaryKey,
          'docs/size-sheet-preview-replay-board-phone-390.png',
        );
      }
    });
  }, skip: !enabled);
}
