// Dev tool, not a test: renders the REAL HomeShell — the new bottom nav,
// the My Puzzles page (filled and empty), and the Gallery tab — at phone
// sizes so the owner can judge the look as an image before a device build.
// Skipped unless MY_PUZZLES_PREVIEW=1:
//   MY_PUZZLES_PREVIEW=1 flutter test test/my_puzzles_preview_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/daily_puzzle.dart';
import 'package:jigsaw_puzzle/home_shell.dart';
import 'package:jigsaw_puzzle/my_puzzles_screen.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/studio_surfaces.dart';
import 'package:jigsaw_puzzle/puzzle_completion.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';
import 'package:jigsaw_puzzle/puzzle_select_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  final enabled = previewEnabled('MY_PUZZLES_PREVIEW');
  DateTime fixedNow() => DateTime(2026, 11, 12, 14);

  String doneOn(DateTime day, {int count = 1}) =>
      completionOn(day, count: count).toJsonString();

  testWidgets('render the My Puzzles page and nav at phone sizes', (
    tester,
  ) async {
    final landscapes = imagesInCategory('landscapes');
    final animal = imagesInCategory('animals').first;
    final cozy = imagesInCategory('cozy').first;
    // Two runs mid-way, two finished photos — one of them at two sizes.
    final seeded = {
      puzzleSaveKey(imageId: landscapes[0].id, columns: 12, rows: 8):
          partiallyPlacedSave(
            96,
            placed: 57,
            startedDay: '2026-11-11',
          ).toJsonString(),
      puzzleSaveKey(imageId: animal.id, columns: 6, rows: 4):
          partiallyPlacedSave(
            24,
            placed: 5,
            startedDay: '2026-11-10',
          ).toJsonString(),
      // One photo finished at ALL FOUR sizes: the chip's worst case must
      // render in the preview the owner judges.
      puzzleCompletionKey(imageId: cozy.id, columns: 6, rows: 4): doneOn(
        DateTime(2026, 11, 9),
      ),
      puzzleCompletionKey(imageId: cozy.id, columns: 12, rows: 8): doneOn(
        DateTime(2026, 11, 10),
      ),
      puzzleCompletionKey(imageId: cozy.id, columns: 15, rows: 10): doneOn(
        DateTime(2026, 11, 10),
      ),
      puzzleCompletionKey(imageId: cozy.id, columns: 18, rows: 12): doneOn(
        DateTime(2026, 11, 11),
      ),
      puzzleCompletionKey(imageId: landscapes[1].id, columns: 6, rows: 4):
          doneOn(DateTime(2026, 11, 8), count: 2),
    };
    final inProgressThumbs = [landscapes[0], animal];
    final finishedThumbs = [cozy, landscapes[1]];

    await tester.runAsync(() async {
      // Real fonts: titles render in the theme's Fredoka/Nunito, not the
      // test-default Ahem boxes — and the nav/check icons need the real
      // Material glyphs.
      await loadStudioFonts();
      await loadMaterialIcons();

      Future<void> capture(GlobalKey boundaryKey, String name) =>
          capturePreviewPng(boundaryKey, 'docs/my-puzzles-preview-$name.png');

      Future<void> openMyPuzzlesTab() async {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('My Puzzles'),
          ),
        );
        await tester.pumpAndSettle();
      }

      // The filled page, at the shared judging sizes.
      for (final (width, height, name) in previewPhoneSizes) {
        SharedPreferences.setMockInitialValues(seeded);
        final boundaryKey = GlobalKey();
        await pumpPhoneApp(
          tester,
          HomeShell(clock: fixedNow),
          size: Size(width, height),
          boundaryKey: boundaryKey,
        );
        await tester.pumpAndSettle();
        await openMyPuzzlesTab();

        // Deterministic decode wait: warm the exact image-cache entries the
        // cards' Image.asset(cacheWidth: thumbnailCacheWidth) resolves, then paint a frame.
        await precachePreviewImages(
          tester.element(find.byType(MyPuzzlesScreen)),
          [for (final image in inProgressThumbs) image.assetPath],
          width: TiltedPhotoCard.thumbnailCacheWidth,
        );
        await tester.pump();
        await capture(boundaryKey, name);

        // The Finished tab, once, at the phone width.
        if (name == 'phone-390') {
          await tester.tap(find.text('Finished'));
          await tester.pumpAndSettle();
          await precachePreviewImages(
            tester.element(find.byType(MyPuzzlesScreen)),
            [for (final image in finishedThumbs) image.assetPath],
            width: TiltedPhotoCard.thumbnailCacheWidth,
          );
          await tester.pump();
          await capture(boundaryKey, 'finished-390');
        }
      }

      // The Gallery tab, so the nav bar is judged on the familiar home too.
      {
        SharedPreferences.setMockInitialValues(seeded);
        final boundaryKey = GlobalKey();
        await pumpPhoneApp(
          tester,
          HomeShell(clock: fixedNow),
          boundaryKey: boundaryKey,
        );
        await tester.pumpAndSettle();

        await precachePreviewImages(
          tester.element(find.byType(PuzzleSelectScreen)),
          [
            for (final category in puzzleCategories)
              categoryCoverPath(category.id),
            dailyPuzzleFor(fixedNow()).assetPath,
          ],
          width: TiltedPhotoCard.thumbnailCacheWidth,
        );
        await tester.pump();
        await capture(boundaryKey, 'gallery-390');
      }

      // The empty page: each tab's mascot empty state.
      {
        SharedPreferences.setMockInitialValues({});
        final boundaryKey = GlobalKey();
        await pumpPhoneApp(
          tester,
          HomeShell(clock: fixedNow),
          boundaryKey: boundaryKey,
        );
        await tester.pumpAndSettle();
        await openMyPuzzlesTab();
        await capture(boundaryKey, 'empty-390');

        await tester.tap(find.text('Finished'));
        await tester.pumpAndSettle();
        await capture(boundaryKey, 'empty-finished-390');
      }
    });
  }, skip: !enabled);
}
