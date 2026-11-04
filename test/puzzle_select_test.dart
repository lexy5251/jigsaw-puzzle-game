import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/daily_puzzle.dart';
import 'package:jigsaw_puzzle/daily_streak.dart';
import 'package:jigsaw_puzzle/game_screen.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// Covers the select → size picker → game screen navigation flow.
void main() {
  setUp(() {
    // Backs shared_preferences with an in-memory map; without it the real
    // plugin is missing in tests and storage lookups never complete.
    SharedPreferences.setMockInitialValues({});
  });

  for (final dailyMatchesCatalog in [false, true]) {
    testWidgets('catalog selection and completion use the fixed date when the daily image '
        '${dailyMatchesCatalog ? 'matches' : 'differs'}', (tester) async {
      final now = DateTime(2026, 11, dailyMatchesCatalog ? 20 : 2, 14);
      // Pin both cases so the duplicate-title regression is always exercised.
      expect(
        dailyPuzzleFor(now).title == 'Alpine Lakes Panorama',
        dailyMatchesCatalog,
      );
      await pumpSelectScreen(tester, clock: () => now);

      expect(find.text('Landscapes'), findsOneWidget);

      // Scope to the catalog grids: the daily card can repeat this title.
      final firstImage = find.descendant(
        of: find.byType(GridView),
        matching: find.text('Alpine Lakes Panorama'),
      );
      // The tile may start below the fold. Bring it fully on-screen before
      // tapping, even if it has already been built by the grid.
      await scrollSelectScreenTo(tester, firstImage);
      await tester.tap(firstImage);
      await tester.pumpAndSettle();

      expect(find.text('24 pieces · Easy'), findsOneWidget);
      expect(find.text('60 pieces · Medium'), findsOneWidget);
      expect(find.text('120 pieces · Hard'), findsOneWidget);

      await tester.tap(find.text('24 pieces · Easy'));
      // runAsync lets the real photo load + decode finish while the sheet-close
      // and route animations play. pumpAndSettle would hang here: Flame's game
      // loop keeps scheduling frames forever once the GameWidget mounts.
      late JigsawGame game;
      await tester.runAsync(() async {
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }
        game = tester
            .widget<GameWidget<JigsawGame>>(find.byType(GameWidget<JigsawGame>))
            .game!;
        await game.loaded;
      });
      await tester.pump();

      expect(find.byType(GameScreen), findsOneWidget);
      expect(find.text('Test Photo · 24 pieces'), findsNothing);

      // Simulate Flame's completion notification after navigating from the
      // catalog. Daily credit must use the selection screen's fixed date.
      expect(await game.onCompleted!(), isTrue);
      await tester.pump(const Duration(milliseconds: 950));
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        await const SharedPreferencesDailyStreakStore().completedDays(),
        dailyMatchesCatalog ? {dayKey(now)} : isEmpty,
      );

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(GameScreen), findsNothing);
      expect(firstImage, findsOneWidget);
    });
  }

  testWidgets(
    'catalog size picker scrolls in a short window on an Alpine daily',
    (tester) async {
      tester.view.physicalSize = const Size(800, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime(2026, 11, 20, 14);
      expect(dailyPuzzleFor(now).title, 'Alpine Lakes Panorama');
      await pumpSelectScreen(tester, clock: () => now);
      final catalogImage = find.descendant(
        of: find.byType(GridView),
        matching: find.text('Alpine Lakes Panorama'),
      );
      await scrollSelectScreenTo(tester, catalogImage);
      await tester.tap(catalogImage);
      await tester.pumpAndSettle();

      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(
          of: sheet,
          matching: find.text('Alpine Lakes Panorama'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      final hardOption = find.descendant(
        of: sheet,
        matching: find.text('120 pieces · Hard'),
      );
      expect(hardOption.hitTestable(), findsNothing);
      await tester.scrollUntilVisible(
        hardOption,
        80,
        scrollable: find.descendant(
          of: sheet,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(hardOption.hitTestable(), findsOneWidget);
    },
  );
}
