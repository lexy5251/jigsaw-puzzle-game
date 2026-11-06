import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/daily_puzzle.dart';
import 'package:jigsaw_puzzle/daily_puzzle_card.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// Covers the "Today's painting" card on the selection screen.
void main() {
  // A fixed mid-day moment makes the daily pick and streak deterministic.
  DateTime fixedNow() => DateTime(2026, 11, 6, 14);
  final daily = dailyPuzzleFor(fixedNow());

  testWidgets('shows a live streak that today has not broken yet', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'daily.days': '["2026-11-04", "2026-11-05"]',
    });
    await pumpSelectScreen(tester, clock: fixedNow);
    await tester.pumpAndSettle();

    expect(find.text("TODAY'S PAINTING"), findsOneWidget);
    expect(find.text(daily.title), findsWidgets);
    expect(find.text('Not started'), findsOneWidget);
    expect(find.text('2-day streak'), findsOneWidget);
    expect(find.text('longest: 2 · pots regrow, no pressure'), findsOneWidget);
    // Two bloomed pots on the windowsill.
    expect(find.byIcon(Icons.local_florist), findsNWidgets(2));
  });

  testWidgets('the windowsill reads day states to screen readers', (
    tester,
  ) async {
    // 2026-11-06 is a Friday; Wednesday and Thursday are done. The card is
    // one tap target, so its subtree merges into a single announcement —
    // the day states must be part of it.
    final semantics = tester.ensureSemantics();
    SharedPreferences.setMockInitialValues({
      'daily.days': '["2026-11-04", "2026-11-05"]',
    });
    await pumpSelectScreen(tester, clock: fixedNow);
    await tester.pumpAndSettle();

    final card = tester.getSemantics(find.text("TODAY'S PAINTING"));
    expect(
      card.label,
      stringContainsInOrder([
        'Monday: not done',
        'Wednesday: done',
        'Thursday: done',
        'Friday: today, not done yet',
        'Saturday: upcoming',
      ]),
    );
    semantics.dispose();
  });

  testWidgets('starts gently with no streak at all', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpSelectScreen(tester, clock: fixedNow);
    await tester.pumpAndSettle();

    expect(find.text('A pot blooms for every quiet day.'), findsOneWidget);
    expect(find.textContaining('longest'), findsNothing);
    expect(find.byIcon(Icons.local_florist), findsNothing);
  });

  testWidgets('shows the done state after finishing today', (tester) async {
    SharedPreferences.setMockInitialValues({'daily.days': '["2026-11-06"]'});
    await pumpSelectScreen(tester, clock: fixedNow);
    await tester.pumpAndSettle();

    expect(find.text('Done today ✓'), findsOneWidget);
    expect(find.text('1-day streak'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('tapping the card opens the size picker for the daily image', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpSelectScreen(tester, clock: fixedNow);
    await tester.pumpAndSettle();

    await tester.tap(find.text("TODAY'S PAINTING"));
    await tester.pumpAndSettle();

    expect(find.text('24 pieces'), findsOneWidget);
    // The sheet repeats the daily image's title above the size list.
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(daily.title),
      ),
      findsOneWidget,
    );
  });

  testWidgets('refreshes the daily card at each local midnight', (
    tester,
  ) async {
    var now = DateTime(2026, 11, 8, 23, 59, 59);
    final monday = DateTime(2026, 11, 9);
    final mondayImage = dailyPuzzleFor(monday);
    final size = puzzleSizes.first;
    SharedPreferences.setMockInitialValues({
      'daily.days': '["2026-11-07", "2026-11-08"]',
      puzzleSaveKey(
        imageId: mondayImage.id,
        columns: size.columns,
        rows: size.rows,
      ): PuzzleSaveState(
        trayPieceIndexes: List.generate(size.pieceCount, (index) => index),
        lockedPieceIndexes: const [],
        loosePiecePositions: const {},
        // Only a run begun on the (upcoming) credit day counts as the
        // daily being in progress.
        startedDay: '2026-11-09',
      ).toJsonString(),
    });
    await pumpSelectScreen(tester, clock: () => now);
    await tester.pumpAndSettle();

    final card = find.byType(DailyPuzzleCard);
    expect(find.text('Done today ✓'), findsOneWidget);
    expect(find.byIcon(Icons.local_florist), findsNWidgets(2));

    now = monday;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: card, matching: find.text(mondayImage.title)),
      findsOneWidget,
    );
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('Done today ✓'), findsNothing);
    expect(find.text('2-day streak'), findsOneWidget);
    expect(find.byIcon(Icons.local_florist), findsNothing);

    // A second rollover checks that the timer was rearmed and that the
    // previous daily's progress does not carry over to the new image.
    now = DateTime(2026, 11, 10);
    final tuesdayImage = dailyPuzzleFor(now);
    expect(tuesdayImage.id, isNot(mondayImage.id));
    await tester.pump(const Duration(days: 1));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: card, matching: find.text(tuesdayImage.title)),
      findsOneWidget,
    );
    expect(find.text('Not started'), findsOneWidget);
    expect(find.text('A pot blooms for every quiet day.'), findsOneWidget);

    await tester.tap(find.text("TODAY'S PAINTING"));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(tuesdayImage.title),
      ),
      findsOneWidget,
    );
  });

  testWidgets('refreshes after resuming on a later day', (tester) async {
    var now = DateTime(2026, 11, 6, 14);
    SharedPreferences.setMockInitialValues({'daily.days': '["2026-11-06"]'});
    await pumpSelectScreen(tester, clock: () => now);
    await tester.pumpAndSettle();
    expect(find.text('Done today ✓'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = DateTime(2026, 11, 8, 14);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    // No elapsed timer time: resuming must refresh even when the OS has
    // suspended timers while the app was in the background.
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(DailyPuzzleCard),
        matching: find.text(dailyPuzzleFor(now).title),
      ),
      findsOneWidget,
    );
    expect(find.text('Done today ✓'), findsNothing);
    expect(find.text('Not started'), findsOneWidget);
    expect(find.text('A pot blooms for every quiet day.'), findsOneWidget);
  });
}
