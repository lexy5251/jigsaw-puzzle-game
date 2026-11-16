// Dev tool, not a test: renders the REAL Story tab (fresh, mid-story, the
// end) so the owner can judge the look as images before a device build.
// Skipped unless STORY_PREVIEW=1:
//   STORY_PREVIEW=1 flutter test test/story_preview_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/story_screen.dart';
import 'package:jigsaw_puzzle/story_track.dart';
import 'package:jigsaw_puzzle/studio_surfaces.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  final enabled = previewEnabled('STORY_PREVIEW');

  testWidgets('render the Story tab states at phone sizes', (tester) async {
    await tester.runAsync(() async {
      await loadStudioFonts();
      await loadMaterialIcons();

      Future<GlobalKey> openStory(
        Map<String, Object> seeded, {
        Size size = const Size(390, 844),
      }) async {
        SharedPreferences.setMockInitialValues(seeded);
        final boundaryKey = GlobalKey();
        await pumpPhoneApp(
          tester,
          StoryScreen(clock: previewNow),
          size: size,
          boundaryKey: boundaryKey,
        );
        await tester.pumpAndSettle();
        // Deterministic decode wait: warm the exact cache entries the
        // finished rows resolve, then paint a frame.
        await precachePreviewImages(
          tester.element(find.byType(StoryScreen)),
          [for (final stop in jigsawStory.stops) stop.image.assetPath],
          width: TiltedPhotoCard.thumbnailCacheWidth,
        );
        await tester.pump();
        return boundaryKey;
      }

      // Fresh: header, scene 1 as the mystery card, locked rows below.
      await capturePreviewPng(
        await openStory(finishedSceneEntries(0)),
        'docs/story-preview-fresh-390.png',
      );

      // Mid-story: read scenes with their lines, scene 4 open.
      await capturePreviewPng(
        await openStory(finishedSceneEntries(3)),
        'docs/story-preview-mid-390.png',
      );
      await capturePreviewPng(
        await openStory(finishedSceneEntries(3), size: const Size(320, 568)),
        'docs/story-preview-mid-320.png',
      );

      // The end: THE END header and every scene readable.
      await capturePreviewPng(
        await openStory(finishedSceneEntries(8)),
        'docs/story-preview-end-390.png',
      );
    });
  }, skip: !enabled);
}
