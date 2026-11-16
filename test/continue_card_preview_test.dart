// Dev tool, not a test: renders the REAL home screen wearing the continue
// card (mid-way run above the daily card) so the owner can judge the look
// as images before a device build. Skipped unless CONTINUE_PREVIEW=1:
//   CONTINUE_PREVIEW=1 flutter test test/continue_card_preview_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/daily_puzzle.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_select_screen.dart';
import 'package:jigsaw_puzzle/studio_surfaces.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  final enabled = previewEnabled('CONTINUE_PREVIEW');

  testWidgets('render the home screen with the continue card', (tester) async {
    await tester.runAsync(() async {
      await loadStudioFonts();
      await loadMaterialIcons();

      // The featured run: first non-daily catalog painting, a third into
      // its 100-piece grid — the realistic mid-way state.
      final featured = nonDailyCatalogImages(previewNow()).first;
      final grid = puzzleSizes[1];

      Future<GlobalKey> openHome(Size size) async {
        SharedPreferences.setMockInitialValues({
          seedSaveKey(featured, grid): partiallyPlacedSave(
            grid.pieceCount,
            placed: 34,
            boardWidth: catalogImageWidth,
            savedAt: DateTime(2026, 11, 12, 9),
          ).toJsonString(),
        });
        final boundaryKey = GlobalKey();
        await pumpPhoneApp(
          tester,
          PuzzleSelectScreen(clock: previewNow),
          size: size,
          boundaryKey: boundaryKey,
        );
        await tester.pumpAndSettle();
        // Deterministic decode wait: warm the exact cache entries the card
        // thumbnails and category covers resolve, then paint a frame.
        await precachePreviewImages(
          tester.element(find.byType(PuzzleSelectScreen)),
          [
            featured.assetPath,
            dailyPuzzleFor(previewNow()).assetPath,
            for (final category in puzzleCategories)
              categoryCoverPath(category.id),
          ],
          width: TiltedPhotoCard.thumbnailCacheWidth,
        );
        await tester.pump();
        return boundaryKey;
      }

      // The owner's shared judging sizes, so a verdict made on this
      // harness holds on the others.
      for (final (width, height, name) in previewPhoneSizes) {
        await capturePreviewPng(
          await openHome(Size(width, height)),
          'docs/continue-card-preview-$name.png',
        );
      }
    });
  }, skip: !enabled);
}
