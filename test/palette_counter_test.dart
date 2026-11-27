import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/game_screen.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';

import 'test_helpers.dart';

/// Covers the palette piece-counter in the game screen's app bar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Default test fonts have different metrics from the shipped counter.
  setUpAll(loadStudioFonts);

  late MockSharedPreferences prefs;
  setUp(() {
    // One loose piece on the board, so completePuzzle can settle it.
    prefs = MockSharedPreferences()..install();
    prefs.storage[singlePieceProgressKey] = singleLoosePieceSave()
        .toJsonString();
  });

  testWidgets('counts placed pieces live', (tester) async {
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
    );

    expect(find.text('0 / 1'), findsOneWidget);
    expect(find.text('pieces placed'), findsOneWidget);

    await completePuzzle(tester, game);

    expect(find.text('1 / 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // Scale 3 covers the counter's own clamp: past 2x the title stops
  // growing (the two fixed action buttons leave it no more width).
  for (final width in [320.0, 375.0, 390.0, 800.0]) {
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets('counter fits width $width at text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        const size = PuzzleSize(columns: 18, rows: 12);
        prefs.storage['flutter.save.test.18x12'] = PuzzleSaveState(
          trayPieceIndexes: [for (var i = 200; i < 216; i++) i],
          lockedPieceIndexes: [for (var i = 0; i < 200; i++) i],
          loosePiecePositions: const {},
          boardWidth: testPhotoWidth,
        ).toJsonString();
        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              theme: studioTheme(),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const GameScreen(
                          image: singlePieceImage,
                          size: size,
                        ),
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          // Flame schedules frames continuously; only finish the route's
          // transition here, then wait explicitly for the board load.
          for (var i = 0; i < 20; i++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          await currentGame(tester).loaded;
        });
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(find.byType(BackButton), findsOneWidget);
        final bar = tester.getRect(find.byType(AppBar));
        // Legibility floor: the FittedBox may shrink the counter when the
        // tools pill starves the title slot, but the load-bearing number
        // must never drop below readable — silent over-shrink would pass
        // every containment check above.
        expect(tester.getRect(find.text('200 / 216')).height, greaterThan(12));
        for (final text in ['200 / 216', 'pieces placed']) {
          final finder = find.text(text);
          final paragraph = tester.renderObject<RenderParagraph>(finder);
          final rect = tester.getRect(finder);
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(bar.contains(rect.topLeft), isTrue);
          expect(bar.contains(rect.bottomRight), isTrue);
        }
        expect(
          find.bySemanticsLabel('200 of 216 pieces placed'),
          findsOneWidget,
        );
        // The whole tools pill fits the same width/scale matrix beside
        // the counter — constant tooltips are the finder handles per the
        // e2e stable-handle rule.
        for (final tooltip in [
          'Edges only',
          'Return to tray',
          'Image preview',
          'Options',
        ]) {
          expect(find.byTooltip(tooltip).hitTestable(), findsOneWidget);
        }
        await tester.tap(find.byTooltip('Edges only'));
        await tester.pump();
        expect(
          tester.widget<EdgesOnlyToggle>(find.byType(EdgesOnlyToggle)).selected,
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
