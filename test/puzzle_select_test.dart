import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/completion_card.dart';
import 'package:jigsaw_puzzle/daily_puzzle.dart';
import 'package:jigsaw_puzzle/daily_streak.dart';
import 'package:jigsaw_puzzle/game_screen.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// Covers the select → size picker → game screen navigation flow.
void main() {
  test('every catalog size keeps columns == rows so pieces stay square', () {
    // Catalog images are square (the 2026-11 1:1 regeneration); any other
    // grid ratio stretches the pieces (the 2026-11-05 phone-test finding).
    for (final size in puzzleSizes) {
      expect(size.columns, size.rows, reason: '${size.columns}x${size.rows}');
    }
  });

  setUp(() {
    // Backs shared_preferences with an in-memory map; without it the real
    // plugin is missing in tests and storage lookups never complete.
    SharedPreferences.setMockInitialValues({});
  });

  for (final dailyMatchesCatalog in [false, true]) {
    testWidgets('catalog selection and completion use the fixed date when the daily image '
        '${dailyMatchesCatalog ? 'matches' : 'differs'}', (tester) async {
      // Pinned to the current 70-image catalog: an Alpine day vs not.
      final now = dailyMatchesCatalog
          ? DateTime(2026, 12, 12, 14)
          : DateTime(2026, 11, 2, 14);
      // Pin both cases so the duplicate-title regression is always exercised.
      expect(
        dailyPuzzleFor(now).title == 'Alpine Lake Morning',
        dailyMatchesCatalog,
      );
      await pumpSelectScreen(tester, clock: () => now);

      // Categories live on their own pages now: open Landscapes first.
      final landscapesCard = find.text('Landscapes');
      await scrollSelectScreenTo(tester, landscapesCard);
      await tester.tap(landscapesCard);
      await tester.pumpAndSettle();

      // Cards carry no visible title; the semantics identifier is the hook.
      final firstImage = catalogPuzzleCard('alpine-lakes-panorama');
      // The tile may start below the fold. Bring it fully on-screen before
      // tapping, even if it has already been built by the grid.
      await scrollSelectScreenTo(tester, firstImage);
      await tester.tap(firstImage);
      await tester.pumpAndSettle();

      expect(find.text('25 pieces'), findsOneWidget);
      expect(find.text('100 pieces'), findsOneWidget);
      expect(find.text('144 pieces'), findsOneWidget);
      expect(find.text('225 pieces'), findsOneWidget);

      await tester.tap(find.text('25 pieces'));
      // runAsync lets the real photo load + decode finish while the sheet-close
      // and route animations play. pumpAndSettle would hang here: Flame's game
      // loop keeps scheduling frames forever once the GameWidget mounts.
      late JigsawGame game;
      await tester.runAsync(() async {
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }
        game = currentGame(tester);
        await game.loaded;
      });
      await tester.pump();

      expect(find.byType(GameScreen), findsOneWidget);
      expect(find.text('Test Photo · 25 pieces'), findsNothing);

      // Simulate Flame's completion notification after navigating from the
      // catalog. Daily credit must use the selection screen's fixed date.
      expect(await game.onCompleted!(), isTrue);
      await tester.pump(GameScreen.completionRevealDelay);
      await tester.pump(CompletionCard.fadeDuration);
      // Extra frame: the fade tween must land on 1 before the card's
      // buttons accept taps (its IgnorePointer guards the fade).
      await tester.pump();
      expect(
        await const SharedPreferencesDailyStreakStore().completedDays(),
        dailyMatchesCatalog ? {dayKey(now)} : isEmpty,
      );

      // The completion card covers the app bar, so the exit is its own
      // "Back to gallery" button, not the page-back arrow.
      await tester.tap(find.text('Back to gallery'));
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

      // An Alpine daily under the current 70-image catalog.
      final now = DateTime(2026, 12, 12, 14);
      expect(dailyPuzzleFor(now).title, 'Alpine Lake Morning');
      await pumpSelectScreen(tester, clock: () => now);

      final landscapesCard = find.text('Landscapes');
      await scrollSelectScreenTo(tester, landscapesCard);
      await tester.tap(landscapesCard);
      await tester.pumpAndSettle();

      final catalogImage = catalogPuzzleCard('alpine-lakes-panorama');
      await scrollSelectScreenTo(tester, catalogImage);
      await tester.tap(catalogImage);
      await tester.pumpAndSettle();

      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(
          of: sheet,
          matching: find.text('Alpine Lake Morning'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      // The last option starts below the short sheet's fold.
      final lastOption = find.descendant(
        of: sheet,
        matching: find.text('225 pieces'),
      );
      expect(lastOption.hitTestable(), findsNothing);
      await tester.scrollUntilVisible(
        lastOption,
        80,
        scrollable: find.descendant(
          of: sheet,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(lastOption.hitTestable(), findsOneWidget);
    },
  );
}
