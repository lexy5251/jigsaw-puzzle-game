// Analytics is decoration: silent by default, and gameplay reports through
// whatever sink is installed. These suites pin both halves — the silent
// default, and that the key moments reach the sink exactly when something
// really happened (no-op taps and replayed completions must not count).

import 'package:flame/game.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/analytics.dart';
import 'package:jigsaw_puzzle/game_screen.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';

import 'test_helpers.dart';

void main() {
  test('the default sink is silent — nothing leaves the device', () {
    expect(Analytics.instance, isA<NoopAnalytics>());
  });

  group('gameplay events', () {
    late MockSharedPreferences prefs;
    late RecordingAnalytics analytics;

    setUp(() {
      prefs = MockSharedPreferences()..install();
      analytics = RecordingAnalytics()..install();
    });

    testWidgets('finishing a board reports the completion', (tester) async {
      prefs.storage[singlePieceProgressKey] = singleLoosePieceSave()
          .toJsonString();
      final game = await bootGameScreen(
        tester,
        image: singlePieceImage,
        size: singlePieceSize,
        catalogs: const PuzzleCatalogs(gallery: chainTestCatalog),
      );
      await completePuzzle(tester, game);

      expect(analytics.events, contains('completed:test:1'));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the completion event survives failing record writes', (
      tester,
    ) async {
      prefs.storage[singlePieceProgressKey] = singleLoosePieceSave()
          .toJsonString();
      final game = await bootGameScreen(
        tester,
        image: singlePieceImage,
        size: singlePieceSize,
      );
      // Every write fails: this is the path that retains a finished save
      // for retry. The event must already be out — it belongs to the
      // finish the player saw, not to the storage outcome.
      prefs.onWrite = (_) => false;
      await completePuzzle(tester, game);

      expect(analytics.events, contains('completed:test:1'));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('resuming an already-finished save does NOT re-report it', (
      tester,
    ) async {
      // An interrupted final snap's leftovers: fully placed, still on disk.
      prefs.storage[singlePieceProgressKey] = PuzzleSaveState(
        trayPieceIndexes: const [],
        lockedPieceIndexes: const [0],
        loosePiecePositions: const {},
        boardWidth: testPhotoWidth,
      ).toJsonString();
      await bootGameScreen(
        tester,
        image: singlePieceImage,
        size: singlePieceSize,
      );
      // Let the on-load celebration's record retry run to its end.
      await tester.pump(GameScreen.completionRevealDelay);
      await tester.pump();

      expect(
        analytics.events.where((e) => e.startsWith('completed:')),
        isEmpty,
        reason: 'The on-load celebration is a replay, not a new finish.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a launch reports its source, and a chain hop reports both '
        'the acceptance and a next_chain start', (tester) async {
      await launchPuzzleFlowToSheet(
        tester,
        image: singlePieceImage,
        catalogs: const PuzzleCatalogs(gallery: chainTestCatalog),
      );
      expect(analytics.events, isEmpty, reason: 'The sheet alone is no run.');

      // The sheet opens on the smallest real size (5x5): the started event
      // carries the sheet's pick, not the fixture's native grid.
      await tester.tap(find.bySemanticsIdentifier('puzzle-start'));
      await tester.runAsync(() => settleLaunchedGame(tester));
      expect(analytics.events, ['started:test:25:gallery']);

      // Pop with a painting, exactly as the completion card's button does.
      Navigator.of(
        tester.element(find.byType(GameScreen)),
      ).pop(secondTestImage);
      await tester.runAsync(() => settleLaunchedGame(tester));
      expect(analytics.events, [
        'started:test:25:gallery',
        'next:test-b',
        'started:test-b:25:nextChain',
      ]);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Start over reports a restart-sourced start', (tester) async {
      prefs.storage[singlePieceProgressKey] = singleLoosePieceSave()
          .toJsonString();
      await bootGameScreen(
        tester,
        image: singlePieceImage,
        size: singlePieceSize,
      );

      await confirmRestartViaMenu(tester);
      await pumpRoute(tester);

      expect(analytics.events, contains('started:test:1:restart'));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the tray controls report edges-only, and tidy only when '
        'the sweep moves something', (tester) async {
      const size = PuzzleSize(columns: 6, rows: 4);
      // One loose piece so the first Tidy has real work to do.
      prefs.storage[saveKeyFor(singlePieceImage, columns: 6, rows: 4)] =
          PuzzleSaveState(
            trayPieceIndexes: [for (var i = 1; i < 24; i++) i],
            lockedPieceIndexes: const [],
            loosePiecePositions: {0: grid6x4Home(0) + Vector2(300, 220)},
            boardWidth: testPhotoWidth,
          ).toJsonString();
      await bootGameScreen(tester, image: singlePieceImage, size: size);

      await tester.tap(find.text('Edges only'));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tap(find.byTooltip('Return to tray'));
      await tester.pump(const Duration(milliseconds: 16));
      expect(analytics.events, ['edges:on', 'tidy']);

      // Nothing left to sweep: the second tap must not count.
      await tester.tap(find.byTooltip('Return to tray'));
      await tester.pump(const Duration(milliseconds: 16));
      expect(analytics.events, ['edges:on', 'tidy']);
    });

    testWidgets('Zoom in reports only steps that move the camera', (
      tester,
    ) async {
      await bootGameScreen(
        tester,
        image: singlePieceImage,
        size: singlePieceSize,
      );
      await openOptionsMenu(tester);

      // Two effective doublings reach the 4x ceiling; the third tap is a
      // no-op and must not count.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Zoom in'));
        await tester.pump();
      }

      expect(analytics.events, ['zoom', 'zoom']);
    });

    testWidgets('picking a board color reports it; re-picking does not', (
      tester,
    ) async {
      await bootGameScreen(
        tester,
        image: singlePieceImage,
        size: singlePieceSize,
      );
      await openOptionsMenu(tester);

      await tester.tap(find.bySemanticsLabel('Board color: Slate'));
      await tester.pump();
      expect(analytics.events, ['color:slate']);

      // The swatch stays tappable while selected — not a change, no event.
      await tester.tap(find.bySemanticsLabel('Board color: Slate'));
      await tester.pump();
      expect(analytics.events, ['color:slate']);
    });
  });
}
