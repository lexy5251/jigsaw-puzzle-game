// The completion card's Collection notes (hand-placement era, owner ruling
// 2026-11-26): a first finish shows one quiet "piece waiting" line — the
// placing itself happens on the Collection board — while replays, gift
// finishes, failed writes, and a full track say nothing. The journey's
// unlock section still fires exactly on the 5th first finish and outranks
// the line.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/bonus_track.dart';
import 'package:jigsaw_puzzle/daily_puzzle.dart';
import 'package:jigsaw_puzzle/game_screen.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
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

  Finder pieceLine() => find.text('A new piece is waiting in your Collection.');

  testWidgets('a first finish notes the piece waiting in Collection', (
    tester,
  ) async {
    seedDistinctCompletions(10);
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
      catalogs: const PuzzleCatalogs(gifts: giftFixtures),
    );
    await completePuzzle(tester, game);

    expect(pieceLine(), findsOneWidget);
    // The old gift section is gone for good: no board completes here —
    // the player places the pieces by hand in Collection.
    expect(find.text('BONUS PUZZLE UNLOCKED'), findsNothing);
    expect(find.text('Play now'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('filling the board by earning alone still only notes a piece', (
    tester,
  ) async {
    // 24 on record + this finish = 25 earned. Earning never unlocks the
    // gift anymore — its board completes in Collection, by hand.
    seedDistinctCompletions(bonusBoardPieces - 1);
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
      catalogs: const PuzzleCatalogs(gifts: giftFixtures),
    );
    await completePuzzle(tester, game);

    expect(pieceLine(), findsOneWidget);
    expect(find.text('Gift One'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a write landing after the reveal leaves the card unchanged', (
    tester,
  ) async {
    // Wedged storage: the card reveals first, the completion write lands
    // seconds later. The line must NOT pop into the interactive card (it
    // would shove the buttons mid-tap) — the piece waits silently in
    // Collection instead.
    seedDistinctCompletions(10);
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

    expect(find.text('FINISHED'), findsOneWidget);
    expect(pieceLine(), findsNothing);

    // The delayed write resolves; the revealed card must not reflow.
    await tester.pump(const Duration(seconds: 6));
    expect(pieceLine(), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a replay earns nothing and says nothing', (tester) async {
    // The photo under test is already on record: this run is a replay, so
    // the distinct-id count cannot move.
    seedDistinctCompletions(10);
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

    expect(find.text('FINISHED'), findsOneWidget);
    expect(pieceLine(), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('finishing a gift itself earns nothing (owner ruling)', (
    tester,
  ) async {
    // The finished painting IS a gift: gifts are rewards, not currency.
    seedDistinctCompletions(10);
    prefs.storage[saveKeyFor(giftImageOne)] = singleLoosePieceSave()
        .toJsonString();
    final game = await bootGameScreen(
      tester,
      image: giftImageOne,
      size: singlePieceSize,
      catalogs: const PuzzleCatalogs(gifts: giftFixtures),
    );
    await completePuzzle(tester, game);

    expect(find.text('FINISHED'), findsOneWidget);
    expect(pieceLine(), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a story scene finish funds the board like any painting', (
    tester,
  ) async {
    // Scenes are NOT gifts: their first finish is currency (owner ruling,
    // 2026-11-14). (A scene REPLAY adds no distinct id — the replay test
    // above covers that path for every image kind.)
    seedDistinctCompletions(10);
    prefs.storage[saveKeyFor(sceneImageOne)] = singleLoosePieceSave()
        .toJsonString();
    final game = await bootGameScreen(
      tester,
      image: sceneImageOne,
      size: singlePieceSize,
      catalogs: const PuzzleCatalogs(gifts: giftFixtures, story: sceneFixtures),
    );
    await completePuzzle(tester, game);

    expect(pieceLine(), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pieces past the last board fund nothing and say nothing', (
    tester,
  ) async {
    // Both fixture boards' worth of pieces already earned: the track is
    // full, so a further first finish must not promise a piece that no
    // board will ever offer.
    seedDistinctCompletions(giftFixtures.length * bonusBoardPieces);
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
      catalogs: const PuzzleCatalogs(gifts: giftFixtures),
    );
    await completePuzzle(tester, game);

    expect(find.text('FINISHED'), findsOneWidget);
    expect(pieceLine(), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a failed completion write notes nothing', (tester) async {
    // The note must mirror what storage holds: the retained save retries
    // the write later, and the piece is noted on the retry that lands.
    seedDistinctCompletions(10);
    prefs.onWrite = (key) => key != singlePieceCompletionKey;
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
      catalogs: const PuzzleCatalogs(gifts: giftFixtures),
    );
    await completePuzzle(tester, game);

    expect(find.text('FINISHED'), findsOneWidget);
    expect(pieceLine(), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('journey unlock', () {
    Finder journeySection() => find.text('THE JOURNEY OPENS');

    testWidgets('the 5th first finish opens the journey on the card', (
      tester,
    ) async {
      seedDistinctCompletions(journeyUnlockFinishes - 1);
      final game = await bootGameScreen(
        tester,
        image: singlePieceImage,
        size: singlePieceSize,
        catalogs: const PuzzleCatalogs(gifts: giftFixtures),
      );
      await completePuzzle(tester, game);

      expect(journeySection(), findsOneWidget);
      // Four prior finishes plus this one, no streak pieces banked.
      expect(find.text('You start with 5 pieces.'), findsOneWidget);
      expect(
        find.textContaining('Your first finish of each painting and every 3'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'See the collection'),
        findsOneWidget,
      );
      // One moment, not two: the journey section already sends the player
      // to Collection, pieces and all.
      expect(pieceLine(), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a finish past the unlock shows no journey section', (
      tester,
    ) async {
      seedDistinctCompletions(journeyUnlockFinishes);
      final game = await bootGameScreen(
        tester,
        image: singlePieceImage,
        size: singlePieceSize,
        catalogs: const PuzzleCatalogs(gifts: giftFixtures),
      );
      await completePuzzle(tester, game);

      expect(journeySection(), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('banked streak pieces ride into the journey head start', (
      tester,
    ) async {
      // 4 finishes + 20 banked streak pieces (60 consecutive days); the
      // 5th finish opens the journey with all 25 waiting to be placed —
      // nothing rolls over by itself anymore.
      seedDistinctCompletions(journeyUnlockFinishes - 1);
      prefs.storage['flutter.daily.days'] = jsonEncode([
        for (var i = 0; i < 60; i++)
          dayKey(DateTime.utc(2026, 1, 1).add(Duration(days: i))),
      ]);
      final game = await bootGameScreen(
        tester,
        image: singlePieceImage,
        size: singlePieceSize,
        catalogs: const PuzzleCatalogs(gifts: giftFixtures),
      );
      await completePuzzle(tester, game);

      expect(journeySection(), findsOneWidget);
      expect(pieceLine(), findsNothing);
      expect(find.text('You start with 25 pieces.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('See the collection pops the game with the request', (
      tester,
    ) async {
      seedDistinctCompletions(journeyUnlockFinishes - 1);
      late Future<Object?> pushed;
      late JigsawGame game;
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(home: const Scaffold(body: Text('base'))),
        );
        pushed = tester
            .state<NavigatorState>(find.byType(Navigator))
            .push<Object>(
              MaterialPageRoute<Object>(
                builder: (_) => GameScreen(
                  image: singlePieceImage,
                  size: singlePieceSize,
                  catalogs: const PuzzleCatalogs(gifts: giftFixtures),
                ),
              ),
            );
        // Build the route, then wait out its transition before grabbing
        // the game.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        game = currentGame(tester);
        await game.loaded;
      });
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await completePuzzle(tester, game);

      await tester.ensureVisible(find.text('See the collection'));
      await tester.tap(find.text('See the collection'));
      await pumpRoute(tester);

      expect(find.text('base'), findsOneWidget);
      // The pop already landed; awaiting through runAsync (real async)
      // just unwraps the completed future's value.
      expect(
        await tester.runAsync(() => pushed),
        isA<OpenCollectionRequest>(),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
