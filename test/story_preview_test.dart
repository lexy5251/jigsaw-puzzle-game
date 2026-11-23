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
        double scrollBy = 0,
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
        // finished rows resolve, then paint a frame. The real awaits also
        // give the screen's async load the event-loop turns it needs
        // under runAsync — the trail exists only after it lands.
        await precachePreviewImages(
          tester.element(find.byType(StoryScreen)),
          [for (final stop in jigsawStory.stops) stop.image.assetPath],
          width: TiltedPhotoCard.thumbnailCacheWidth,
        );
        await tester.pumpAndSettle();
        if (scrollBy != 0) {
          await tester.drag(find.byType(Scrollable).first, Offset(0, -scrollBy));
          await tester.pumpAndSettle();
        }
        await tester.pump();
        return boundaryKey;
      }

      // Fresh: scene 1 waits as the bow-tied parcel on its slot.
      await capturePreviewPng(
        await openStory(finishedSceneEntries(0)),
        'docs/story-preview-fresh-390.png',
      );

      // Mid-story, at rest: three read stops on the trail, scene 4's
      // parcel waiting, slots fading below.
      Map<String, Object> midRest({bool torn = false}) => Map.fromEntries([
        ...finishedSceneEntries(3).entries,
        storyCelebratedEntry(3, torn: torn),
      ]);
      await capturePreviewPng(
        await openStory(midRest()),
        'docs/story-preview-mid-390.png',
      );
      await capturePreviewPng(
        await openStory(midRest(), size: const Size(320, 568)),
        'docs/story-preview-mid-320.png',
      );

      // The same spot with the parcel torn open into the mystery card
      // (scrolled to it — the card sits mid-trail).
      await capturePreviewPng(
        await openStory(midRest(torn: true), scrollBy: 760),
        'docs/story-preview-mid-torn-390.png',
      );

      // The end: THE END header, the whole trail read, the plaque
      // (scrolled to the trail's end where it blooms).
      await capturePreviewPng(
        await openStory(
          Map.fromEntries([
            ...finishedSceneEntries(8).entries,
            storyCelebratedEntry(8, finale: true),
          ]),
          scrollBy: 4000,
        ),
        'docs/story-preview-end-390.png',
      );
    });
  }, skip: !enabled);
}
