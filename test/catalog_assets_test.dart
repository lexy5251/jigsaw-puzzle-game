import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';

/// Catalog entries and photo files are hand-synced (photo drops rename and
/// replace files in bulk), so a typo or missing file would otherwise surface
/// only as a dead tile or a failed game load on a device.
void main() {
  test('every catalog image has its photo on disk', () {
    // fullPuzzleCatalog covers the gift-only bonus paintings too — they
    // load through the same game path as gallery images.
    final missing = [
      for (final image in fullPuzzleCatalog)
        if (!File(image.assetPath).existsSync()) image.assetPath,
    ];

    expect(missing, isEmpty, reason: 'catalog entries without a bundled file');
  });

  test('gift and story paintings stay off every browsing surface', () {
    final galleryCategories = {
      for (final category in puzzleCategories) category.id,
    };
    // One loop per special catalog: a future track (a holiday story, say)
    // joins by adding its list here, not by copying the whole test.
    const specialCatalogs = {
      'bonus': bonusPuzzleCatalog,
      'story': storyPuzzleCatalog,
    };
    for (final MapEntry(key: name, value: special) in specialCatalogs.entries) {
      for (final image in special) {
        // The category id staying off the Gallery's list is what keeps
        // these paintings out of every browsing surface.
        expect(
          galleryCategories,
          isNot(contains(image.categoryId)),
          reason: '$name image ${image.id} leaks into a gallery category',
        );
      }
    }
    // The data-level markers must agree with the list each image sits in —
    // checked across the FULL catalog, so gallery images are pinned as
    // neither gift nor scene in the same sweep.
    for (final image in fullPuzzleCatalog) {
      expect(image.isBonus, bonusPuzzleCatalog.contains(image));
      expect(image.isStory, storyPuzzleCatalog.contains(image));
    }
  });

  test('ids are unique across the full catalog', () {
    // Completion records are keyed by id, so a collision anywhere — not
    // just between a known pair of lists — would merge two paintings'
    // progress.
    final ids = [for (final image in fullPuzzleCatalog) image.id];
    expect(ids.toSet().length, ids.length, reason: 'duplicate catalog ids');
  });

  test('every catalog photo is encoded at catalogImageWidth', () async {
    // The one-tap resume guard trusts [catalogImageWidth] to mean "the
    // resolution saves restore against"; a regeneration that changes the
    // assets without updating the constant would quietly break that
    // promise. Header-only decode, so sweeping the full catalog stays
    // cheap.
    final wrong = <String>[];
    for (final image in fullPuzzleCatalog) {
      final bytes = File(image.assetPath).readAsBytesSync();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width != catalogImageWidth) {
        wrong.add('${image.assetPath}: ${descriptor.width}px');
      }
      descriptor.dispose();
      buffer.dispose();
    }

    expect(
      wrong,
      isEmpty,
      reason:
          'assets not at catalogImageWidth ($catalogImageWidth px) — '
          'regenerated catalog? Update the constant in puzzle_catalog.dart',
    );
  });

}
