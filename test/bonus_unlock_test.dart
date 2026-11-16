// The "Bonus puzzle unlocked" moment on the completion card: it appears
// exactly when a completion's writes cross a 25-piece boundary, "Play now"
// rides the next-puzzle chain, "Save for later" tucks the section away, and
// replays, gift finishes, or failed writes never unlock anything.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/bonus_track.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_completion.dart';

import 'test_helpers.dart';

void main() {
  late MockSharedPreferences prefs;

  setUp(() {
    prefs = MockSharedPreferences()..install();
    prefs.storage[singlePieceProgressKey] = singleLoosePieceSave()
        .toJsonString();
  });

  /// [count] distinct finished photos already on record — the pieces earned
  /// before the run under test. One short of a board is 24.
  void seedDistinctCompletions(int count) {
    for (var i = 0; i < count; i++) {
      prefs.storage['flutter.${puzzleCompletionKey(imageId: 'seed-$i', columns: 5, rows: 5)}'] =
          completionJson(DateTime(2026, 11, 1));
    }
  }

  Finder bonusSection() => find.text('BONUS PUZZLE UNLOCKED');

  testWidgets('the finish that completes a board unlocks its gift', (
    tester,
  ) async {
    seedDistinctCompletions(bonusBoardPieces - 1);
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
      catalogs: const PuzzleCatalogs(gifts: giftFixtures),
    );
    await completePuzzle(tester, game);

    expect(bonusSection(), findsOneWidget);
    expect(find.text('Gift One'), findsOneWidget);
    expect(find.text('Saved to your Collection.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Play now'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Save for later'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Save for later tucks the section away, the card stays', (
    tester,
  ) async {
    seedDistinctCompletions(bonusBoardPieces - 1);
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
      catalogs: const PuzzleCatalogs(gifts: giftFixtures),
    );
    await completePuzzle(tester, game);

    // The gift section can sit below the fold of the card's scroll view.
    await tester.ensureVisible(find.text('Save for later'));
    await tester.tap(find.text('Save for later'));
    await tester.pump();

    expect(bonusSection(), findsNothing);
    // The completion card itself is untouched — only the gift section goes.
    expect(find.textContaining('no timer, no score'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Play now pops with the gift painting (the chain input)', (
    tester,
  ) async {
    seedDistinctCompletions(bonusBoardPieces - 1);
    final route = await pushGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
      catalogs: const PuzzleCatalogs(gifts: giftFixtures),
    );
    await completePuzzle(tester, currentGame(tester));

    // The gift section can sit below the fold of the card's scroll view.
    await tester.ensureVisible(find.text('Play now'));
    await tester.tap(find.text('Play now'));
    await tester.pumpAndSettle();

    expect(route.popResult?.id, giftImageOne.id);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a write landing after the reveal leaves the card unchanged', (
    tester,
  ) async {
    // Wedged storage: the card reveals first, the completion write lands
    // seconds later. The gift section must NOT pop into the interactive
    // card (it would shove the buttons mid-tap) — the gift waits silently
    // in Collection instead.
    seedDistinctCompletions(bonusBoardPieces - 1);
    prefs.onWrite = (key) async {
      if (key == singlePieceCompletionKey) {
        await Future<void>.delayed(const Duration(seconds: 5));
      }
      return true;
    };
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
      catalogs: const PuzzleCatalogs(gifts: giftFixtures),
    );
    await completePuzzle(tester, game);

    expect(find.textContaining('no timer, no score'), findsOneWidget);
    expect(bonusSection(), findsNothing);

    // The delayed write resolves; the revealed card must not reflow.
    await tester.pump(const Duration(seconds: 6));
    expect(bonusSection(), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a replay crosses no boundary and unlocks nothing', (
    tester,
  ) async {
    // The photo under test is already on record: this run is a replay, so
    // the distinct-id count cannot move even though the board sits full.
    seedDistinctCompletions(bonusBoardPieces - 1);
    prefs.storage[singlePieceCompletionKey] = completionJson(
      DateTime(2026, 11, 1),
    );
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
      catalogs: const PuzzleCatalogs(gifts: giftFixtures),
    );
    await completePuzzle(tester, game);

    expect(bonusSection(), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('finishing a gift itself earns nothing (owner ruling)', (
    tester,
  ) async {
    // One piece short, and the finished painting IS a gift: the filter
    // must keep the board at 24 — gifts are rewards, not currency.
    seedDistinctCompletions(bonusBoardPieces - 1);
    prefs.storage[saveKeyFor(giftImageOne)] = singleLoosePieceSave()
        .toJsonString();
    final game = await bootGameScreen(
      tester,
      image: giftImageOne,
      size: singlePieceSize,
      catalogs: const PuzzleCatalogs(gifts: giftFixtures),
    );
    await completePuzzle(tester, game);

    expect(find.textContaining('no timer, no score'), findsOneWidget);
    expect(bonusSection(), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a story scene finish funds the board like any painting', (
    tester,
  ) async {
    // Scenes are NOT gifts: their first finish is currency (owner ruling,
    // 2026-11-14), so the 25th piece landing from a scene unlocks the gift.
    // (A scene REPLAY adds no distinct id — the replay test above covers
    // that path for every image kind.)
    seedDistinctCompletions(bonusBoardPieces - 1);
    prefs.storage[saveKeyFor(sceneImageOne)] = singleLoosePieceSave()
        .toJsonString();
    final game = await bootGameScreen(
      tester,
      image: sceneImageOne,
      size: singlePieceSize,
      catalogs: const PuzzleCatalogs(gifts: giftFixtures, story: sceneFixtures),
    );
    await completePuzzle(tester, game);

    expect(bonusSection(), findsOneWidget);
    expect(find.text('Gift One'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mid-board finishes celebrate the puzzle only', (tester) async {
    seedDistinctCompletions(10);
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
      catalogs: const PuzzleCatalogs(gifts: giftFixtures),
    );
    await completePuzzle(tester, game);

    expect(find.textContaining('no timer, no score'), findsOneWidget);
    expect(bonusSection(), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a failed completion write never unlocks', (tester) async {
    // The unlock must mirror what storage holds: the retained save retries
    // the write later, and the gift fires on the retry that lands instead.
    seedDistinctCompletions(bonusBoardPieces - 1);
    prefs.onWrite = (key) => key != singlePieceCompletionKey;
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
      catalogs: const PuzzleCatalogs(gifts: giftFixtures),
    );
    await completePuzzle(tester, game);

    expect(find.textContaining('no timer, no score'), findsOneWidget);
    expect(bonusSection(), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
