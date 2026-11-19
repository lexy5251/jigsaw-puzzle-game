// Dev tool, not a test: renders the REAL home gallery scrolled to one
// category card so a new category's cover, tint and mascot can be judged
// as images before a device build. Skipped unless CATEGORY_CARD_PREVIEW=1:
//   CATEGORY_CARD_PREVIEW=1 flutter test test/category_card_preview_test.dart
// Pick the card with CATEGORY_CARD_PREVIEW_CATEGORY (default: food, the
// category currently under judgment).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/daily_puzzle.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_select_screen.dart';
import 'package:jigsaw_puzzle/studio_surfaces.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  final enabled = previewEnabled('CATEGORY_CARD_PREVIEW');

  testWidgets('render the gallery scrolled to a category card', (tester) async {
    await tester.runAsync(() async {
      await loadStudioFonts();
      await loadMaterialIcons();

      final categoryId =
          Platform.environment['CATEGORY_CARD_PREVIEW_CATEGORY'] ?? 'food';
      final category = puzzleCategories.firstWhere((c) => c.id == categoryId);

      // The owner's shared judging sizes, so a verdict made on this
      // harness holds on the others.
      for (final (width, height, name) in previewPhoneSizes) {
        SharedPreferences.setMockInitialValues({});
        final boundaryKey = GlobalKey();
        await pumpPhoneApp(
          tester,
          PuzzleSelectScreen(clock: previewNow),
          size: Size(width, height),
          boundaryKey: boundaryKey,
        );
        await tester.pumpAndSettle();

        // Deterministic decode wait: warm the exact cache entries the daily
        // card and category covers resolve, then paint a frame.
        await precachePreviewImages(
          tester.element(find.byType(PuzzleSelectScreen)),
          [
            dailyPuzzleFor(previewNow()).assetPath,
            for (final c in puzzleCategories) categoryCoverPath(c.id),
          ],
          width: TiltedPhotoCard.thumbnailCacheWidth,
        );
        await tester.pump();

        await scrollSelectScreenTo(tester, find.text(category.title));
        await capturePreviewPng(
          boundaryKey,
          'docs/category-card-preview-$categoryId-$name.png',
        );
      }
    });
  }, skip: !enabled);
}
