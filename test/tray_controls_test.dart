// The control row riding on the tray's top edge: the "Edges only" filter
// chip (moved down from the app bar) and the Return-to-tray sweep.
// The game-level sweep rules live in return_to_tray_test; this suite pins
// the Flutter wiring, the row's placement in the reserved band, and the
// fade that keeps the row out of a carried piece's way.

import 'package:flame/game.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/game_screen.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
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

  void seedSave({Map<int, Vector2> loose = const {}}) {
    prefs.storage[gridSaveKey] = PuzzleSaveState(
      trayPieceIndexes: [
        for (var i = 0; i < 24; i++)
          if (!loose.containsKey(i)) i,
      ],
      lockedPieceIndexes: const [],
      loosePiecePositions: loose,
      boardWidth: testPhotoWidth,
    ).toJsonString();
  }

  testWidgets('the Edges only chip toggles the tray filter', (tester) async {
    seedSave();
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: size,
    );
    expect(game.visibleTrayPieceIndexes, hasLength(24));

    await tester.tap(find.text('Edges only'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.visibleTrayPieceIndexes, hasLength(16));
    expect(
      tester.widget<EdgesOnlyToggle>(find.byType(EdgesOnlyToggle)).selected,
      isTrue,
    );

    // The same chip switches back to all pieces.
    await tester.tap(find.text('Edges only'));
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

  testWidgets('the row sits exactly in the band above the tray', (
    tester,
  ) async {
    seedSave();
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: size,
    );
    final trayHeight = game.trayHeightOnScreen.value;
    expect(trayHeight, greaterThan(0));

    final bodyBottom = tester
        .getRect(find.byType(GameWidget<JigsawGame>))
        .bottom;
    final bandTop = bodyBottom - trayHeight - game.controlRowHeight;
    for (final finder in [
      find.byType(EdgesOnlyToggle),
      find.byTooltip('Return to tray'),
    ]) {
      final rect = tester.getRect(finder);
      expect(rect.top, greaterThanOrEqualTo(bandTop - 0.01));
      expect(rect.bottom, lessThanOrEqualTo(bodyBottom - trayHeight + 0.01));
    }
  });

  testWidgets('the row fades out while a piece is carried', (tester) async {
    seedSave(loose: {8: grid6x4Home(8) + Vector2(300, 220)});
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: size,
    );
    final piece = game.world.children.whereType<PuzzlePiece>().single;

    Finder rowOpacity() => find
        .ancestor(of: find.byType(EdgesOnlyToggle), matching: find.byType(Opacity))
        .first;
    double rowOpacityValue() => tester.widget<Opacity>(rowOpacity()).opacity;
    expect(rowOpacityValue(), 1.0);
    expect(find.text('Edges only').hitTestable(), findsOneWidget);

    // A carried piece must never hide behind (or drop onto) the buttons,
    // so the row yields taps the moment the finger owns a piece.
    expect(game.beginPieceDrag(piece), isTrue);
    await tester.pump();
    expect(find.text('Edges only').hitTestable(), findsNothing);
    await tester.pump(const Duration(milliseconds: 120));
    expect(rowOpacityValue(), 0.0);

    game.settlePiece(piece, allowTrayReturn: false);
    await tester.pump();
    // Mid-fade-in the row is already drawing but still takes no taps: a
    // button the player cannot see yet must not swallow a board tap.
    await tester.pump(const Duration(milliseconds: 60));
    expect(rowOpacityValue(), greaterThan(0.0));
    expect(rowOpacityValue(), lessThan(1.0));
    expect(find.text('Edges only').hitTestable(), findsNothing);

    await tester.pump(const Duration(milliseconds: 60));
    expect(rowOpacityValue(), 1.0);
    expect(find.text('Edges only').hitTestable(), findsOneWidget);
  });

  testWidgets('the row fits a narrow screen with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    seedSave();
    await bootGameScreen(tester, image: singlePieceImage, size: size);
    expect(tester.takeException(), isNull); // No overflow.
    // The slim labels fit even here — both stay visible and tappable,
    // and the sweep keeps its explanatory tooltip.
    expect(find.text('Edges only').hitTestable(), findsOneWidget);
    expect(find.text('Tidy').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Return to tray').hitTestable(), findsOneWidget);
  });
}
