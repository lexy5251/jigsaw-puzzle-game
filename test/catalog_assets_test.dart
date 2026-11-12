import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';

/// Catalog entries and photo files are hand-synced (photo drops rename and
/// replace files in bulk), so a typo or missing file would otherwise surface
/// only as a dead tile or a failed game load on a device.
void main() {
  test('every catalog image has its photo on disk', () {
    final missing = [
      for (final image in puzzleCatalog)
        if (!File(image.assetPath).existsSync()) image.assetPath,
    ];

    expect(missing, isEmpty, reason: 'catalog entries without a bundled file');
  });

  test('every category has its cover on disk', () {
    // Covers fall back to the first catalog photo at the call site, so a
    // missing one is not fatal — but it is always a packaging mistake.
    final missing = [
      for (final category in puzzleCategories)
        if (!File(categoryCoverPath(category.id)).existsSync())
          categoryCoverPath(category.id),
    ];

    expect(missing, isEmpty, reason: 'categories without a cover file');
  });
}
