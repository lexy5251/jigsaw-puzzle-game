// Dev tool, not a test: renders the REAL CategoryScreen (UI-6 two-across
// photo grid, no titles) at phone sizes so the owner can judge the layout
// as an image before a device build. Skipped unless CATEGORY_GRID_PREVIEW=1:
//   CATEGORY_GRID_PREVIEW=1 flutter test test/category_grid_preview_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/category_screen.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/studio_surfaces.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  final enabled = previewEnabled('CATEGORY_GRID_PREVIEW');

  testWidgets('render the category grid at phone sizes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      // Real fonts: the AppBar title renders in the theme's Fredoka, not
      // the test-default Ahem boxes.
      await loadStudioFonts();

      final category = puzzleCategories.firstWhere((c) => c.id == 'landscapes');

      // The shared judging sizes.
      for (final (width, height, name) in previewPhoneSizes) {
        final boundaryKey = GlobalKey();
        await pumpPhoneApp(
          tester,
          CategoryScreen(category: category),
          size: Size(width, height),
          boundaryKey: boundaryKey,
        );

        // Deterministic decode wait: warm the exact image-cache entries the
        // grid's Image.asset(cacheWidth: thumbnailCacheWidth) resolves, then paint a frame.
        await precachePreviewImages(
          tester.element(find.byType(CategoryScreen)),
          [for (final image in imagesInCategory(category.id)) image.assetPath],
          width: TiltedPhotoCard.thumbnailCacheWidth,
        );
        await tester.pump();

        await capturePreviewPng(
          boundaryKey,
          'docs/category-grid-preview-$name.png',
        );
      }
    });
  }, skip: !enabled);
}
