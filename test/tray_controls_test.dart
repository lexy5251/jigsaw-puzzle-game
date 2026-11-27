// The play tools in the app bar's pill: the "Edges only" filter toggle
// and the Return-to-tray sweep (moved up from the old band above the tray
// — the owner's pick of the genre layout). The game-level sweep rules
// live in return_to_tray_test; this suite pins the Flutter wiring, the
// pill's placement in the app bar (no reserved band left below), and the
// filter's self-dismissal when the frame completes.

import 'package:flame/game.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/game_screen.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_logic.dart';
import 'package:jigsaw_puzzle/puzzle_piece.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';

import 'test_helpers.dart';

void main() {
  const size = PuzzleSize(columns: 6, rows: 4);
  final gridSaveKey = saveKeyFor(singlePieceImage, columns: 6, rows: 4);

  late MockSharedPreferences prefs;

  setUp(() {
    prefs = MockSharedPreferences()..install();
  });

  void seedSave({
    Map<int, Vector2> loose = const {},
    List<int> locked = const [],
  }) {
    prefs.storage[gridSaveKey] = PuzzleSaveState(
      trayPieceIndexes: [
        for (var i = 0; i < 24; i++)
          if (!loose.containsKey(i) && !locked.contains(i)) i,
      ],
      lockedPieceIndexes: locked,
      loosePiecePositions: loose,
      boardWidth: testPhotoWidth,
    ).toJsonString();
  }

  testWidgets('the Edges only toggle filters the tray', (tester) async {
    seedSave();
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: size,
    );
    expect(game.visibleTrayPieceIndexes, hasLength(24));

    await tester.tap(find.byTooltip('Edges only'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.visibleTrayPieceIndexes, hasLength(16));
    expect(
      tester.widget<EdgesOnlyToggle>(find.byType(EdgesOnlyToggle)).selected,
      isTrue,
    );

    // The same toggle switches back to all pieces.
    await tester.tap(find.byTooltip('Edges only'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.visibleTrayPieceIndexes, hasLength(24));
    expect(
      tester.widget<EdgesOnlyToggle>(find.byType(EdgesOnlyToggle)).selected,
      isFalse,
    );
  });

  testWidgets('Return to tray sweeps the loose pieces back', (tester) async {
    seedSave(
      loose: {8: grid6x4Home(8) + Vector2(300, 220), 14: grid6x4Home(14)},
    );
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: size,
    );
    expect(game.trayPieceIndexes, hasLength(22));

    await tester.tap(find.byTooltip('Return to tray'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    // The tap reached the game's sweep; the sweep's own rules (and its
    // save) are pinned in return_to_tray_test.
    expect(game.trayPieceIndexes, hasLength(24));
  });

  testWidgets('both tools live in the app bar and no band is reserved', (
    tester,
  ) async {
    seedSave();
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: size,
    );

    // The screen draws no overlay over the board — both tools render
    // inside the AppBar, leaving the game canvas alone below it.
    expect(game.trayHeightOnScreen.value, greaterThan(0));
    for (final tooltip in ['Edges only', 'Return to tray']) {
      expect(
        find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(AppBar),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('the tools stay usable while a piece is carried', (
    tester,
  ) async {
    seedSave(loose: {8: grid6x4Home(8) + Vector2(300, 220)});
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: size,
    );
    final piece = game.world.children.whereType<PuzzlePiece>().single;

    // The old band faded out under a carried piece because it floated
    // over the board. The app bar is outside the board, so the tools
    // must stay visible and tappable mid-carry.
    expect(game.beginPieceDrag(piece), isTrue);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byTooltip('Edges only').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Return to tray').hitTestable(), findsOneWidget);
    game.settlePiece(piece, allowTrayReturn: false);
    await tester.pump();
  });

  testWidgets('the filter dismisses itself when the frame completes', (
    tester,
  ) async {
    // Every edge piece locked but one, parked off its cell (exactly-home
    // loose pieces re-lock during restore and would finish the frame at
    // boot).
    final edges = [
      for (var i = 0; i < 24; i++)
        if (isEdgePiece(i, 6, 4)) i,
    ];
    expect(edges, hasLength(16));
    seedSave(
      locked: [...edges.where((i) => i != 0)],
      loose: {0: grid6x4Home(0) + Vector2(140, 90)},
    );
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: size,
    );
    expect(game.frameComplete, isFalse);

    await tester.tap(find.byTooltip('Edges only'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      tester.widget<EdgesOnlyToggle>(find.byType(EdgesOnlyToggle)).selected,
      isTrue,
    );

    // Locking the last edge piece completes the frame; the filter must
    // switch itself off and the tray show the interior pieces again.
    final piece = game.world.children
        .whereType<PuzzlePiece>()
        .firstWhere((p) => !p.isLocked);
    expect(game.beginPieceDrag(piece), isTrue);
    final home = grid6x4Home(0);
    piece.position.setValues(home.x, home.y);
    game.settlePiece(piece, allowTrayReturn: false);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(game.frameComplete, isTrue);
    expect(
      tester.widget<EdgesOnlyToggle>(find.byType(EdgesOnlyToggle)).selected,
      isFalse,
    );
    expect(game.visibleTrayPieceIndexes, hasLength(8));
  });

  testWidgets('the filter cannot be enabled over a finished frame', (
    tester,
  ) async {
    // Frame already complete at boot: every edge piece locked. Enabling
    // the filter would show an empty tray and hide the interior pieces
    // the player still needs, so the toggle must refuse.
    final edges = [
      for (var i = 0; i < 24; i++)
        if (isEdgePiece(i, 6, 4)) i,
    ];
    seedSave(locked: edges);
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: size,
    );
    expect(game.frameComplete, isTrue);
    expect(game.visibleTrayPieceIndexes, hasLength(8));

    await tester.tap(find.byTooltip('Edges only'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      tester.widget<EdgesOnlyToggle>(find.byType(EdgesOnlyToggle)).selected,
      isFalse,
    );
    expect(game.visibleTrayPieceIndexes, hasLength(8));
  });

  testWidgets('the pill fits a narrow screen with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    seedSave();
    await bootGameScreen(tester, image: singlePieceImage, size: size);
    expect(tester.takeException(), isNull); // No overflow.
    // Icons don't scale with text, so every tool keeps its full tap
    // target even here.
    for (final tooltip in [
      'Edges only',
      'Return to tray',
      'Image preview',
      'Options',
    ]) {
      expect(find.byTooltip(tooltip).hitTestable(), findsOneWidget);
    }
  });
}
