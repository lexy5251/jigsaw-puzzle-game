// Full UI flow: start a puzzle, back out, re-open the size sheet — the
// 'In progress' label must be there (2026-11-06 phone report).
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  DateTime fixedNow() => DateTime(2026, 11, 6, 14);

  testWidgets('back out of a fresh run, label shows on reopen', (
    tester,
  ) async {
    MockSharedPreferences().install();
    await pumpSelectScreen(tester, clock: fixedNow);
    await tester.pumpAndSettle();

    // Open the first grid puzzle's size sheet (layout B: the whole catalog
    // sits on the home grid, no category page in between).
    final firstCard = catalogPuzzleCard('alpine-lakes-panorama');
    await scrollSelectScreenTo(tester, firstCard);
    await tester.tap(firstCard);
    await tester.pumpAndSettle();
    // Fresh puzzle: the smallest size is pre-selected and reads as a start.
    expect(find.text('Start · 25 pieces'), findsOneWidget);
    expect(find.textContaining('In progress'), findsNothing);

    // Start the 25-piece game and let it fully load (writes the fresh save).
    await tester.tap(find.bySemanticsIdentifier('puzzle-start'));
    await tester.runAsync(() async {
      await tester.pumpAndSettle();
      final game = currentGame(tester);
      await game.loaded;
      await game.progressSaved;
    });
    await tester.pump(const Duration(milliseconds: 50));

    // Back to the home grid.
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Re-open the same puzzle's sheet: the saved run must be pre-selected,
    // wearing its progress mark, with a resume (not restart) button. The
    // fresh save may have grown a continue card above, shifting the grid —
    // scroll the tile back into reach before tapping.
    await scrollSelectScreenTo(tester, firstCard);
    await tester.tap(firstCard);
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(
        'puzzle-in-progress-alpine-lakes-panorama-5x5',
      ),
      findsOneWidget,
    );
    expect(find.text('Resume · 25 pieces'), findsOneWidget);
  });
}
