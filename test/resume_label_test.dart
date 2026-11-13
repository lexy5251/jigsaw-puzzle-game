// Full UI flow: start a puzzle, back out, re-open the size sheet — the
// 'In progress' label must be there (2026-11-06 phone report).
import 'package:flutter/material.dart';
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

    // Open the first category, then its first puzzle's size sheet.
    await tester.tap(find.bySemanticsIdentifier('category-landscapes'));
    await tester.pumpAndSettle();
    final firstCard = find.byType(GridView);
    expect(firstCard, findsOneWidget);
    await tester.tap(
      find.descendant(of: firstCard, matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('25 pieces'), findsOneWidget);
    expect(find.textContaining('In progress'), findsNothing);

    // Start the 24-piece game and let it fully load (writes the fresh save).
    await tester.tap(find.text('25 pieces'));
    await tester.runAsync(() async {
      await tester.pumpAndSettle();
      final game = currentGame(tester);
      await game.loaded;
      await game.progressSaved;
    });
    await tester.pump(const Duration(milliseconds: 50));

    // Back to the category page.
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Re-open the same puzzle's sheet: the label must be there.
    await tester.tap(
      find.descendant(of: find.byType(GridView), matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('In progress'), findsOneWidget);
  });
}
