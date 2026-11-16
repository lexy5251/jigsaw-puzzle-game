import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/daily_puzzle.dart';
import 'package:jigsaw_puzzle/daily_puzzle_card.dart';
import 'package:jigsaw_puzzle/game_screen.dart';
import 'package:jigsaw_puzzle/my_puzzles.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';
import 'package:jigsaw_puzzle/puzzle_select_screen.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// The home "Continue puzzle" card: when it shows, which run it picks, and
/// that its tap reopens the run directly — no size sheet in between.
void main() {
  final now = DateTime(2026, 11, 2, 14);
  final daily = dailyPuzzleFor(now);
  final others = nonDailyCatalogImages(now);

  // A function, not a shared finder: semantics finders can only be built
  // while a test's semantics tree is live.
  Finder continueCard() => find.bySemanticsIdentifier('continue-puzzle');

  /// A resumable seed at the CURRENT catalog resolution — the width stamp
  /// is what lets the one-tap path restore instead of falling back.
  String resumableSeed(
    PuzzleSize size, {
    int placed = 0,
    String? startedDay,
    required DateTime savedAt,
  }) => partiallyPlacedSave(
    size.pieceCount,
    placed: placed,
    startedDay: startedDay,
    boardWidth: catalogImageWidth,
    savedAt: savedAt,
  ).toJsonString();

  testWidgets('no unfinished puzzle, no continue card', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    await pumpSelectScreen(tester, clock: () => now);
    await tester.pumpAndSettle();

    expect(continueCard(), findsNothing);
  });

  testWidgets('nothing renders before the first status load lands', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      seedSaveKey(others.first, puzzleSizes[0]): resumableSeed(
        puzzleSizes[0],
        savedAt: DateTime(2026, 11, 1, 9),
      ),
    });
    await pumpSelectScreen(tester, clock: () => now, settle: false);

    // First frame: no content at all — the continue card must never pop in
    // ABOVE an already-painted daily card and shift a tap in flight.
    expect(find.byType(DailyPuzzleCard), findsNothing);

    await tester.pumpAndSettle();
    expect(find.byType(DailyPuzzleCard), findsOneWidget);
    expect(continueCard(), findsOneWidget);
  });

  testWidgets('the newest run shows its progress and resumes in one tap', (
    tester,
  ) async {
    final older = others[0];
    final newer = others[1];
    final size = puzzleSizes[1]; // 10x10, 100 pieces
    SharedPreferences.setMockInitialValues({
      seedSaveKey(older, puzzleSizes[0]): resumableSeed(
        puzzleSizes[0],
        savedAt: DateTime(2026, 11, 1, 9),
      ),
      seedSaveKey(newer, size): resumableSeed(
        size,
        placed: 30,
        savedAt: DateTime(2026, 11, 1, 21),
      ),
    });
    await pumpSelectScreen(tester, clock: () => now);
    await tester.pumpAndSettle();

    // The 21:00 save outranks the 09:00 one, whole catalog considered.
    expect(continueCard(), findsOneWidget);
    expect(
      find.descendant(of: continueCard(), matching: find.text(newer.title)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: continueCard(),
        matching: find.text('30 of 100 pieces'),
      ),
      findsOneWidget,
    );

    await tester.tap(continueCard());
    // Every pump after the tap stays inside runAsync: the game mounts on
    // the first post-tap frame (no sheet animation in between), and a
    // photo decode started outside runAsync never completes.
    await tester.runAsync(() => settleLaunchedGame(tester));
    await tester.pump();

    // Straight into the game: the size sheet never opened.
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    // The save actually restored — the tap resumed, not restarted.
    expect(find.bySemanticsLabel('Puzzle board, resumed'), findsOneWidget);
  });

  testWidgets('a crediting daily run is left to the daily card', (
    tester,
  ) async {
    final other = others.first;
    SharedPreferences.setMockInitialValues({
      // The daily's own run is the newest save by far, and (startedDay ==
      // today) it credits a pot — the daily card owns it...
      seedSaveKey(daily, puzzleSizes[0]): resumableSeed(
        puzzleSizes[0],
        startedDay: dayKey(now),
        savedAt: DateTime(2026, 11, 2, 12),
      ),
      // ...so the card must skip it for the older non-daily run.
      seedSaveKey(other, puzzleSizes[0]): resumableSeed(
        puzzleSizes[0],
        savedAt: DateTime(2026, 11, 1, 9),
      ),
    });
    await pumpSelectScreen(tester, clock: () => now);
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: continueCard(), matching: find.text(other.title)),
      findsOneWidget,
    );
    // The daily card still owns its own run's status.
    expect(find.text(statusInProgressLabel), findsOneWidget);
  });

  testWidgets('only a crediting daily run, card stays hidden', (tester) async {
    SharedPreferences.setMockInitialValues({
      seedSaveKey(daily, puzzleSizes[0]): resumableSeed(
        puzzleSizes[0],
        startedDay: dayKey(now),
        savedAt: DateTime(2026, 11, 2, 12),
      ),
    });
    await pumpSelectScreen(tester, clock: () => now);
    await tester.pumpAndSettle();

    expect(continueCard(), findsNothing);
  });

  testWidgets("a NON-crediting run of today's daily still gets the card", (
    tester,
  ) async {
    // Begun weeks ago from a category, so dailyCreditDay rejects it: the
    // daily card shows 'Not started' — without the card, the most recently
    // played run would have no resume surface on home all day.
    SharedPreferences.setMockInitialValues({
      seedSaveKey(daily, puzzleSizes[0]): resumableSeed(
        puzzleSizes[0],
        startedDay: '2026-10-01',
        savedAt: DateTime(2026, 11, 2, 12),
      ),
    });
    await pumpSelectScreen(tester, clock: () => now);
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: continueCard(), matching: find.text(daily.title)),
      findsOneWidget,
    );
    expect(find.text('Not started'), findsOneWidget);
  });

  testWidgets('a fully placed run is never offered as a continue', (
    tester,
  ) async {
    // The interrupted-final-snap leftover: all pieces locked, no record.
    SharedPreferences.setMockInitialValues({
      seedSaveKey(others.first, puzzleSizes[0]): resumableSeed(
        puzzleSizes[0],
        placed: puzzleSizes[0].pieceCount,
        savedAt: DateTime(2026, 11, 2, 12),
      ),
      seedSaveKey(others[1], puzzleSizes[0]): resumableSeed(
        puzzleSizes[0],
        placed: 3,
        savedAt: DateTime(2026, 11, 1, 9),
      ),
    });
    await pumpSelectScreen(tester, clock: () => now);
    await tester.pumpAndSettle();

    // '25 of 25 pieces' must never headline the home screen; the older
    // real run is offered instead.
    expect(
      find.descendant(of: continueCard(), matching: find.text(others[1].title)),
      findsOneWidget,
    );
  });

  testWidgets('a bonus painting can be the run the card offers', (
    tester,
  ) async {
    // The newest run is a Collection gift — outside the gallery catalog.
    // The card must agree with My Puzzles (full catalog) and show it.
    final gift = bonusPuzzleCatalog.first;
    SharedPreferences.setMockInitialValues({
      seedSaveKey(gift, puzzleSizes[0]): resumableSeed(
        puzzleSizes[0],
        placed: 4,
        savedAt: DateTime(2026, 11, 2, 12),
      ),
      seedSaveKey(others.first, puzzleSizes[0]): resumableSeed(
        puzzleSizes[0],
        savedAt: DateTime(2026, 11, 1, 9),
      ),
    });
    await pumpSelectScreen(tester, clock: () => now);
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: continueCard(), matching: find.text(gift.title)),
      findsOneWidget,
    );
  });

  testWidgets('a stale card falls back to the size sheet', (tester) async {
    final image = others.first;
    final size = puzzleSizes[0];
    SharedPreferences.setMockInitialValues({
      seedSaveKey(image, size): resumableSeed(
        size,
        savedAt: DateTime(2026, 11, 1, 9),
      ),
    });
    await pumpSelectScreen(tester, clock: () => now);
    await tester.pumpAndSettle();
    expect(continueCard(), findsOneWidget);

    // The save vanishes behind the screen's back (e.g. finished or wiped
    // from another tab); the card is now stale.
    await const SharedPreferencesSaveStore().delete(seedSaveKey(image, size));
    await tester.tap(continueCard());
    await tester.pumpAndSettle();

    // No silent restart: the size sheet opens instead of the game.
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(GameScreen), findsNothing);
    expect(find.text('Start · ${size.pieceCount} pieces'), findsOneWidget);
  });

  testWidgets('a width-mismatched save falls back to the sheet too', (
    tester,
  ) async {
    // A legacy save from an older catalog resolution: the game's scale
    // guard would restart it fresh, so the one-tap path must refuse and
    // open the sheet instead of silently wiping the advertised progress.
    final image = others.first;
    final size = puzzleSizes[0];
    SharedPreferences.setMockInitialValues({
      seedSaveKey(image, size): partiallyPlacedSave(
        size.pieceCount,
        placed: 7,
        boardWidth: 9999,
        savedAt: DateTime(2026, 11, 1, 9),
      ).toJsonString(),
    });
    await pumpSelectScreen(tester, clock: () => now);
    await tester.pumpAndSettle();
    // The summary still lists it (owner-ruled), so the card shows it...
    expect(continueCard(), findsOneWidget);

    await tester.tap(continueCard());
    await tester.pumpAndSettle();

    // ...but the tap goes to the sheet, never a silent fresh board.
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(GameScreen), findsNothing);
  });

  test('continueRunFrom applies the page rules in list order', () {
    InProgressRun runOf(PuzzleImage image, {int placed = 0}) =>
        InProgressRun(image: image, size: puzzleSizes[0], placedCount: placed);
    expect(continueRunFrom(const []), isNull);
    // The daily is skipped only when its id is passed (credit-owned).
    expect(continueRunFrom([runOf(daily)], excludedDailyId: daily.id), isNull);
    expect(continueRunFrom([runOf(daily)])!.image.id, daily.id);
    expect(
      continueRunFrom([
        runOf(daily),
        runOf(others[0]),
        runOf(others[1]),
      ], excludedDailyId: daily.id)!.image.id,
      others[0].id,
    );
    // Fully placed runs never surface.
    expect(
      continueRunFrom([
        runOf(others[0], placed: puzzleSizes[0].pieceCount),
        runOf(others[1]),
      ])!.image.id,
      others[1].id,
    );
  });
}
