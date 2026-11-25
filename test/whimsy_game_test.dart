// Whimsies through the real load path: the plan derives from the save key,
// so the same puzzle always carries the same figures (resume, restart, and
// the next-chain all re-enter the same load), fixture grids stay whimsy-free,
// and gameplay keeps treating a whimsy piece as its plain base cell.

import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_logic.dart';
import 'package:jigsaw_puzzle/whimsy_plan.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('a 5x5 board hides one interior whimsy from its pool', (
    tester,
  ) async {
    final game = await bootBareGame(
      tester,
      columns: 5,
      rows: 5,
      saveKey: 'save.test.5x5',
    );
    expect(game.whimsyPlan.cells, hasLength(1));
    final cell = game.whimsyPlan.cells.keys.single;
    expect(isEdgePiece(cell, 5, 5), isFalse);
    expect(
      universalWhimsyShapes,
      contains(game.whimsyPlan.cells.values.single),
    );
  });

  testWidgets('the same save key always cuts the same whimsies', (
    tester,
  ) async {
    Future<WhimsyPlan> planFor(String saveKey) async {
      final game = await bootBareGame(
        tester,
        columns: 5,
        rows: 5,
        saveKey: saveKey,
      );
      return game.whimsyPlan;
    }

    final layout = Map.of((await planFor('save.test.5x5')).cells);

    // A second game on the same key — what restart, resume and the next
    // chain all do — must reproduce the layout exactly.
    expect((await planFor('save.test.5x5')).cells, layout);

    expect((await planFor('save.test-b.5x5')).cells, hasLength(1));
  });

  testWidgets('fixture grids outside the catalog stay whimsy-free', (
    tester,
  ) async {
    final game = await bootBareGame(tester);
    expect(game.whimsyPlan.isEmpty, isTrue);
  });

  testWidgets('the edges-only filter hides the interior whimsy piece', (
    tester,
  ) async {
    final game = await bootBareGame(
      tester,
      columns: 5,
      rows: 5,
      saveKey: 'save.test.5x5',
    );
    final whimsyCell = game.whimsyPlan.cells.keys.single;

    game.setEdgesOnlyFilter(true);
    await tester.pump(const Duration(milliseconds: 16));

    // 5x5: 16 edge pieces visible; the whimsy is interior by construction
    // and must be filtered out with the rest of the interior.
    expect(game.visibleTrayPieceIndexes.length, 16);
    expect(game.visibleTrayPieceIndexes, isNot(contains(whimsyCell)));
    expect(game.trayPieceIndexes, contains(whimsyCell));
  });

  group('with the real screen wiring', () {
    late MockSharedPreferences prefs;

    setUp(() {
      prefs = MockSharedPreferences()..install();
    });

    testWidgets('the game screen passes the image pool through', (
      tester,
    ) async {
      final game = await bootGameScreen(
        tester,
        image: singlePieceImage,
        size: const PuzzleSize(columns: 5, rows: 5),
      );
      expect(prefs.storage, isNotEmpty); // the fresh board saved itself
      expect(game.whimsyPlan.cells, hasLength(1));
      expect(
        whimsyPoolFor(singlePieceImage),
        contains(game.whimsyPlan.cells.values.single),
      );
    });
  });
}
