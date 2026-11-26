// Dev tool, not a test: renders the REAL home screen in the daily card's
// three states (not started / in progress / done) so the owner can judge
// the status-line removal as images before a device build. Skipped unless
// DAILY_PREVIEW=1:
//   DAILY_PREVIEW=1 flutter test test/daily_card_preview_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/daily_puzzle.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_completion.dart';
import 'package:jigsaw_puzzle/puzzle_select_screen.dart';
import 'package:jigsaw_puzzle/studio_surfaces.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  final enabled = previewEnabled('DAILY_PREVIEW');

  testWidgets('render the daily card in its three states', (tester) async {
    await tester.runAsync(() async {
      await loadStudioFonts();
      await loadMaterialIcons();

      final daily = dailyPuzzleFor(previewNow());
      final today = dayKey(previewNow());

      // The three states the card can wear. The in-progress seed is a
      // crediting run (begun today), so the card offers Continue and the
      // continue card stays hidden — the state the player actually sees.
      final states = <String, Map<String, Object>>{
        'fresh': {},
        'in-progress': {
          seedSaveKey(daily, puzzleSizes.first): fullTraySave(
            puzzleSizes.first.pieceCount,
            startedDay: today,
          ).toJsonString(),
        },
        // A 2-day run ending today, with the journey already open (5
        // finishes seeded): the capture shows the forward hook at its most
        // motivating ("1 day to a bonus piece"). The fresh state above
        // doubles as the pre-unlock render — bold streak line, no hook.
        'done': {
          'daily.days': '["2026-11-11", "$today"]',
          for (var i = 0; i < 5; i++)
            puzzleCompletionKey(imageId: 'seed-$i', columns: 5, rows: 5):
                completionOn(DateTime(2026, 11, 1)).toJsonString(),
        },
      };

      Future<GlobalKey> openHome(Map<String, Object> prefs, Size size) async {
        SharedPreferences.setMockInitialValues(prefs);
        final boundaryKey = GlobalKey();
        await pumpPhoneApp(
          tester,
          PuzzleSelectScreen(clock: previewNow),
          size: size,
          boundaryKey: boundaryKey,
        );
        await tester.pumpAndSettle();
        // Deterministic decode wait: warm the exact cache entries the card
        // thumbnail and the first grid rows resolve, then paint a frame.
        await precachePreviewImages(
          tester.element(find.byType(PuzzleSelectScreen)),
          [
            daily.assetPath,
            for (final painting in puzzleCatalog.take(6)) painting.assetPath,
          ],
          width: TiltedPhotoCard.thumbnailCacheWidth,
        );
        await tester.pump();
        return boundaryKey;
      }

      // The owner's shared judging sizes, so a verdict made on this
      // harness holds on the others.
      for (final (width, height, name) in previewPhoneSizes) {
        for (final state in states.entries) {
          await capturePreviewPng(
            await openHome(state.value, Size(width, height)),
            'docs/daily-card-preview-${state.key}-$name.png',
          );
        }
      }
    });
  }, skip: !enabled);
}
