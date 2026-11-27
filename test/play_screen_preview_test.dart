// Dev tool, not a test: renders the REAL reorganized play screen mid-game —
// board anchored at the top, loose pieces parked in the sorting area, the
// control row riding on the tray — at the judging phone sizes, resting and
// with the Options menu open, so the owner can judge the new layout before
// a device build. Skipped unless PLAY_SCREEN_PREVIEW=1:
//   PLAY_SCREEN_PREVIEW=1 flutter test test/play_screen_preview_test.dart

import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

const _sourcePhoto = 'assets/images/animals/pets_in_the_reading_nook.webp';
const _grid = PuzzleSize(columns: 5, rows: 5);

/// A believable mid-game snapshot: the top frame locked, three loose
/// pieces parked out of the way, the rest in the tray. [roomBelow] parks
/// the loose pieces in the sorting area under the board (the wide-phone
/// case); narrow screens have no room there, so they rest on the board.
PuzzleSaveState _midGameSave(int photoSide, {required bool roomBelow}) {
  final cell = photoSide / _grid.columns;
  const locked = [0, 1, 2, 3, 4, 5, 9, 10];
  final side = photoSide.toDouble();
  final loose = roomBelow
      ? {
          7: Vector2(0.12 * side, side + 0.10 * cell),
          12: Vector2(0.44 * side, side + 0.25 * cell),
          18: Vector2(0.72 * side, side + 0.05 * cell),
        }
      : {
          7: Vector2(0.10 * side, 0.70 * side),
          12: Vector2(0.44 * side, 0.76 * side),
          18: Vector2(0.72 * side, 0.68 * side),
        };
  return PuzzleSaveState(
    trayPieceIndexes: [
      for (var i = 0; i < _grid.pieceCount; i++)
        if (!locked.contains(i) && !loose.containsKey(i)) i,
    ],
    lockedPieceIndexes: locked,
    loosePiecePositions: loose,
    boardWidth: photoSide,
  );
}

/// Flips the Edges only filter on and lets the tray re-filter settle, so
/// the panel shows the toggle's active (tomato circle) state over the
/// edge-only tray.
Future<void> _turnOnEdgesOnly(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Edges only'));
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final enabled = previewEnabled('PLAY_SCREEN_PREVIEW');

  testWidgets('render the reorganized play screen sheet', (tester) async {
    await tester.runAsync(() async {
      await loadStudioFonts();
      await loadMaterialIcons();

      final square = await squareCatalogPhoto(_sourcePhoto);
      // Each panel is its own puzzle id, so every boot resumes the seeded
      // mid-game save for exactly its screen size.
      SharedPreferences.setMockInitialValues({
        for (final (width, _, name) in previewPhoneSizes)
          for (final variant in const ['resting', 'edges', 'menu'])
            puzzleSaveKey(
              imageId: 'play-$name-$variant',
              columns: _grid.columns,
              rows: _grid.rows,
            ): _midGameSave(
              square.width,
              roomBelow: width >= 390,
            ).toJsonString(),
      });

      final panels = <(ui.Image, String)>[];
      try {
        for (final (width, height, name) in previewPhoneSizes) {
          for (final (variant, label) in const [
            ('resting', ''),
            ('edges', ' - edges only on'),
            ('menu', ' - menu open'),
          ]) {
            panels.add((
              await captureGameScreenPanel(
                tester,
                photo: square.clone(),
                panelId: 'play-$name-$variant',
                screenSize: Size(width, height),
                grid: _grid,
                beforeCapture: switch (variant) {
                  'menu' => openOptionsMenu,
                  'edges' => _turnOnEdgesOnly,
                  _ => null,
                },
              ),
              '$name$label',
            ));
          }
        }
      } finally {
        square.dispose();
      }
      await composePreviewSheet(panels, 'docs/play-screen-preview.png');
    });
  }, skip: !enabled);
}
