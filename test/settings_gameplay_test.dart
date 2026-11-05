import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/app_settings.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';

import 'test_helpers.dart';

/// Covers what the settings change in a running game, plus the restart
/// action that ships with the settings feature.
void main() {
  late MockSharedPreferences prefs;

  setUp(() {
    prefs = MockSharedPreferences()..install();
  });

  testWidgets('the ghost preview default starts the hint visible', (
    tester,
  ) async {
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
      settings: const AppSettings(ghostPreviewDefault: true),
    );

    expect(game.ghostPreviewOpacity, greaterThan(0));
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.image))
          .isSelected,
      isTrue,
    );
  });

  testWidgets('without the setting the hint starts hidden', (tester) async {
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
    );
    expect(game.ghostPreviewOpacity, 0);
  });

  testWidgets('restart clears the save and boots a fresh board', (
    tester,
  ) async {
    // A resumed board: the one piece sits loose on the board.
    prefs.storage[singlePieceProgressKey] = singleLoosePieceSave()
        .toJsonString();
    final resumedGame = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
    );
    expect(find.bySemanticsLabel('Puzzle board, resumed'), findsOneWidget);

    // The live Flame game keeps requesting frames, so pumpAndSettle would
    // never settle here — the dialog is driven with fixed pumps instead.
    Future<void> pumpDialog() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
    }

    // Declining keeps the same game and the stored progress.
    await tester.tap(find.byTooltip('Restart puzzle'));
    await pumpDialog();
    expect(find.text('Start over?'), findsOneWidget);
    await tester.tap(find.text('Keep going'));
    await pumpDialog();
    expect(identical(currentGame(tester), resumedGame), isTrue);

    // Confirming swaps in a new game on a save-free board.
    await tester.tap(find.byTooltip('Restart puzzle'));
    await pumpDialog();
    await tester.runAsync(() async {
      await tester.tap(find.text('Start over'));
      await pumpDialog();
      // Let the drain + delete futures complete, then await the new board.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
      await currentGame(tester).loaded;
    });
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(identical(currentGame(tester), resumedGame), isFalse);
    expect(find.bySemanticsLabel('Puzzle board, new puzzle'), findsOneWidget);
    // The fresh board replaced the old snapshot: its piece is back in the
    // tray instead of loose on the board.
    final saved = PuzzleSaveState.fromJsonString(
      prefs.storage[singlePieceProgressKey]! as String,
    );
    expect(saved!.trayPieceIndexes, [0]);
    expect(saved.loosePiecePositions, isEmpty);
  });
}
