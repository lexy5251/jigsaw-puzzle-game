// Dev tool, not a test: renders the REAL layout-B home (filter chips +
// the one catalog grid) so the owner can judge the look as images before
// a device build. Three states per size: fresh install, marked (a 42%
// pill and a done sticker in the first rows — which also grows the
// continue card, as the real app would), and the Landscapes filter
// selected. Skipped unless HOME_PREVIEW=1:
//   HOME_PREVIEW=1 flutter test test/home_gallery_preview_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/daily_puzzle.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_completion.dart';
import 'package:jigsaw_puzzle/puzzle_select_screen.dart';
import 'package:jigsaw_puzzle/studio_surfaces.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  final enabled = previewEnabled('HOME_PREVIEW');

  testWidgets('render the layout-B home', (tester) async {
    await tester.runAsync(() async {
      await loadStudioFonts();
      await loadMaterialIcons();

      // The marked state's actors: the first two non-daily paintings OF
      // THE INTERLEAVED "All" ORDER, so the pill and sticker land in the
      // grid rows the capture shows.
      final daily = dailyPuzzleFor(previewNow());
      final allOrder = [
        for (final painting in interleaveByCategory(puzzleCatalog))
          if (painting.id != daily.id) painting,
      ];
      final started = allOrder.first;
      final completed = allOrder[1];
      final grid = puzzleSizes[1];

      Future<GlobalKey> openHome(
        Size size, {
        required bool seeded,
        String? filterChip,
      }) async {
        SharedPreferences.setMockInitialValues(
          seeded
              ? {
                  seedSaveKey(started, grid): partiallyPlacedSave(
                    grid.pieceCount,
                    placed: 42,
                    boardWidth: catalogImageWidth,
                    savedAt: DateTime(2026, 11, 12, 9),
                  ).toJsonString(),
                  puzzleCompletionKey(
                    imageId: completed.id,
                    columns: 5,
                    rows: 5,
                  ): completionOn(DateTime(2026, 11, 10)).toJsonString(),
                }
              : {},
        );
        final boundaryKey = GlobalKey();
        await pumpPhoneApp(
          tester,
          PuzzleSelectScreen(clock: previewNow),
          size: size,
          boundaryKey: boundaryKey,
        );
        await tester.pumpAndSettle();
        // Deterministic decode wait: warm the exact cache entries the
        // cards and the first grid rows resolve, then paint a frame.
        await precachePreviewImages(
          tester.element(find.byType(PuzzleSelectScreen)),
          [
            daily.assetPath,
            started.assetPath,
            for (final painting in allOrder.take(8)) painting.assetPath,
            for (final painting in imagesInCategory('landscapes').take(8))
              painting.assetPath,
          ],
          width: TiltedPhotoCard.thumbnailCacheWidth,
        );
        await tester.pump();
        if (filterChip != null) {
          await tester.tap(find.bySemanticsIdentifier(filterChip));
          await tester.pumpAndSettle();
        }
        return boundaryKey;
      }

      for (final (width, height, sizeName) in previewPhoneSizes) {
        final size = Size(width, height);
        var key = await openHome(size, seeded: false);
        await capturePreviewPng(
          key,
          'docs/home-gallery-preview-fresh-$sizeName.png',
        );
        key = await openHome(size, seeded: true);
        await capturePreviewPng(
          key,
          'docs/home-gallery-preview-marked-$sizeName.png',
        );
        key = await openHome(
          size,
          seeded: true,
          filterChip: 'category-landscapes',
        );
        await capturePreviewPng(
          key,
          'docs/home-gallery-preview-landscapes-$sizeName.png',
        );
      }
    });
  }, skip: !enabled);
}
