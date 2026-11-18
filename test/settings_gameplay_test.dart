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

  testWidgets('finishing the puzzle buzzes while haptics are on', (
    tester,
  ) async {
    // A loose piece on the board: settling it is the snap under test.
    prefs.storage[singlePieceProgressKey] = singleLoosePieceSave()
        .toJsonString();
    final haptics = RecordingGameHaptics();
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
      haptics: haptics,
    );

    await completeBoard(tester, game);

    // The completing placement buzzes completion only — the snap tap is
    // skipped so the two pulses never overlap. (The non-final snap tap is
    // covered in game_sounds_test.)
    expect(haptics.snaps, 0);
    expect(haptics.completes, 1);
  });

  testWidgets('turning haptics off keeps the device still', (tester) async {
    prefs.storage[singlePieceProgressKey] = singleLoosePieceSave()
        .toJsonString();
    final haptics = RecordingGameHaptics();
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
      settings: const AppSettings(hapticsEnabled: false),
      haptics: haptics,
    );

    await completeBoard(tester, game);

    expect(haptics.snaps, 0);
    expect(haptics.completes, 0);
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
    Future<void> pumpDialog() => pumpRoute(tester);

    // Declining keeps the same game and the stored progress.
    await openRestartDialog(tester);
    expect(find.text('Start over?'), findsOneWidget);
    await tester.tap(find.text('Keep going'));
    await pumpDialog();
    expect(identical(currentGame(tester), resumedGame), isTrue);

    // Confirming swaps in a new game on a save-free board.
    await openRestartDialog(tester);
    await tester.runAsync(() async {
      await tester.tap(startOverDialogButton);
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
