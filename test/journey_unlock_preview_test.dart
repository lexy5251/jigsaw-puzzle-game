// Dev tool, not a test: renders the completion card wearing the journey
// unlock section (5th finish) over a real finished painting, so the owner
// can judge the moment as images before a device build. The pop-in piece
// is captured settled. Skipped unless JOURNEY_PREVIEW=1:
//   JOURNEY_PREVIEW=1 flutter test test/journey_unlock_preview_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/completion_card.dart';
import 'package:jigsaw_puzzle/studio_surfaces.dart';

import 'test_helpers.dart';

void main() {
  final enabled = previewEnabled('JOURNEY_PREVIEW');

  testWidgets('render the journey-unlock completion card', (tester) async {
    await tester.runAsync(() async {
      await loadStudioFonts();
      await loadMaterialIcons();

      // The 5th finish in a realistic session: the finished painting
      // fills the board behind the card, exactly as on device.
      final finished = nonDailyCatalogImages(previewNow()).first;

      Future<GlobalKey> openCard(Size size) async {
        final boundaryKey = GlobalKey();
        await pumpPhoneApp(
          tester,
          Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(finished.assetPath, fit: BoxFit.cover),
              CompletionCard(
                image: finished,
                pieceCount: 25,
                onBackToGallery: () {},
                onNextPuzzle: () {},
                journeyPieces: 5,
                onSeeCollection: () {},
              ),
            ],
          ),
          size: size,
          boundaryKey: boundaryKey,
        );
        await precachePreviewImages(tester.element(find.byType(Stack).first), [
          finished.assetPath,
        ], width: TiltedPhotoCard.thumbnailCacheWidth);
        // Fade-in plus the pickup's elastic pop, fully settled.
        await tester.pumpAndSettle();
        return boundaryKey;
      }

      // The owner's shared judging sizes, so a verdict made on this
      // harness holds on the others.
      for (final (width, height, name) in previewPhoneSizes) {
        await capturePreviewPng(
          await openCard(Size(width, height)),
          'docs/journey-unlock-preview-$name.png',
        );
      }
    });
  }, skip: !enabled);
}
