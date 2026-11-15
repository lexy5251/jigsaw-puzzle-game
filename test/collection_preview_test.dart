// Dev tool, not a test: renders the REAL Collection tab (fresh, mid-board,
// first gift earned) and the completion card wearing the bonus-unlock
// section, so the owner can judge the look as images before a device build.
// Skipped unless COLLECTION_PREVIEW=1:
//   COLLECTION_PREVIEW=1 flutter test test/collection_preview_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/completion_card.dart';
import 'package:jigsaw_puzzle/my_puzzles_screen.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_completion.dart';
import 'package:jigsaw_puzzle/studio_surfaces.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  final enabled = previewEnabled('COLLECTION_PREVIEW');

  /// [count] finished photos on record — the earned pieces of the track.
  /// Real catalog ids (up to 25 of them), so the first two tabs stay
  /// plausible in the same seeded state.
  Map<String, String> seededCompletions(int count) => {
    for (var i = 0; i < count; i++)
      puzzleCompletionKey(imageId: puzzleCatalog[i].id, columns: 5, rows: 5):
          completionJson(DateTime(2026, 11, 1)),
  };

  testWidgets('render the Collection tab states at phone sizes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await loadStudioFonts();
      await loadMaterialIcons();

      Future<GlobalKey> openCollection(
        Map<String, String> seeded, {
        Size size = const Size(390, 844),
      }) async {
        SharedPreferences.setMockInitialValues(seeded);
        final boundaryKey = GlobalKey();
        await pumpPhoneApp(
          tester,
          MyPuzzlesScreen(clock: previewNow),
          size: size,
          boundaryKey: boundaryKey,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Collection'));
        await tester.pumpAndSettle();
        // Deterministic decode wait: warm the exact cache entries the board
        // reveal and gift cards resolve, then paint a frame.
        await precachePreviewImages(
          tester.element(find.byType(MyPuzzlesScreen)),
          [for (final gift in bonusPuzzleCatalog) gift.assetPath],
          width: TiltedPhotoCard.thumbnailCacheWidth,
        );
        await tester.pump();
        return boundaryKey;
      }

      // Before the journey: the teaser invitation (two paintings done).
      await capturePreviewPng(
        await openCollection(seededCompletions(2)),
        'docs/collection-preview-teaser-390.png',
      );

      // Just opened: the fifth finish reveals the board with 5 pieces on.
      await capturePreviewPng(
        await openCollection(seededCompletions(5)),
        'docs/collection-preview-opened-390.png',
      );

      // Mid-board: the guessing stage, scattered pieces across the picture.
      await capturePreviewPng(
        await openCollection(seededCompletions(14)),
        'docs/collection-preview-mid-390.png',
      );
      await capturePreviewPng(
        await openCollection(seededCompletions(14), size: const Size(320, 568)),
        'docs/collection-preview-mid-320.png',
      );

      // First gift earned: it hangs below while the next board starts.
      await capturePreviewPng(
        await openCollection(seededCompletions(25)),
        'docs/collection-preview-unlocked-390.png',
      );
    });
  }, skip: !enabled);

  testWidgets('render the completion card with the bonus unlock', (
    tester,
  ) async {
    final finished = imagesInCategory('landscapes').first;
    await tester.runAsync(() async {
      await loadStudioFonts();
      await loadMaterialIcons();
      SharedPreferences.setMockInitialValues(const {});

      final boundaryKey = GlobalKey();
      await pumpPhoneApp(
        tester,
        Stack(
          children: [
            // Stands in for the blurred board: the default tan backdrop.
            Container(color: const Color(0xFFE7DABD)),
            CompletionCard(
              image: finished,
              pieceCount: 100,
              onBackToGallery: () {},
              onNextPuzzle: () {},
              bonusUnlock: bonusPuzzleCatalog.first,
              onPlayBonus: () {},
              onSaveBonusForLater: () {},
            ),
          ],
        ),
        boundaryKey: boundaryKey,
      );
      await tester.pump(CompletionCard.fadeDuration);
      await tester.pump();
      await precachePreviewImages(
        tester.element(find.byType(CompletionCard)),
        [finished.assetPath, bonusPuzzleCatalog.first.assetPath],
        width: TiltedPhotoCard.thumbnailCacheWidth,
      );
      await tester.pump();
      await capturePreviewPng(
        boundaryKey,
        'docs/bonus-card-preview-390.png',
      );
    });
  }, skip: !enabled);
}
