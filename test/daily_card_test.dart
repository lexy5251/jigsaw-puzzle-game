import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/daily_puzzle.dart';
import 'package:jigsaw_puzzle/daily_puzzle_card.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';
import 'package:jigsaw_puzzle/studio_mascots.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// Covers the "Today's painting" card on the selection screen.
void main() {
  // A fixed mid-day moment makes the daily pick and streak deterministic.
  DateTime fixedNow() => DateTime(2026, 11, 6, 14);
  final daily = dailyPuzzleFor(fixedNow());

  // Scoped to the windowsill strip: the category cards show mascots of
  // their own.
  Finder bloomedPots() => find.descendant(
    of: find.byType(DailyWindowsill),
    matching: find.byWidgetPredicate(
      (widget) => widget is MascotArt && widget.mascot == StudioMascot.cactus,
    ),
  );

  // The card's done marker: the bloomed pot (owner ruling, UI-2). With the
  // status text gone, this is how tests probe the done state.
  Finder doneMarker() => find.descendant(
    of: find.byType(DailyPuzzleCard),
    matching: find.byWidgetPredicate(
      (widget) => widget is MascotArt && widget.mascot == StudioMascot.cactus,
    ),
  );

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
    // The Begin card invites; the rule line explains what blooms a pot.
    expect(find.widgetWithText(FilledButton, 'Begin'), findsOneWidget);
    expect(find.text("Finish it and today's pot blooms."), findsOneWidget);
    // The streak is one quiet line under the windowsill strip.
    expect(find.text('2-day streak · longest: 2'), findsOneWidget);
    // Two bloomed pots on the windowsill.
    expect(bloomedPots(), findsNWidgets(2));
  });

  testWidgets('the windowsill reads day states to screen readers', (
    tester,
  ) async {
    // 2026-11-06 is a Friday; Wednesday and Thursday are done. The strip
    // sits outside the tap target now, so each pot announces itself.
    final semantics = tester.ensureSemantics();
    SharedPreferences.setMockInitialValues({
      'daily.days': '["2026-11-04", "2026-11-05"]',
    });
    await pumpSelectScreen(tester, clock: fixedNow);
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Monday: not done'), findsOneWidget);
    expect(find.bySemanticsLabel('Wednesday: done'), findsOneWidget);
    expect(find.bySemanticsLabel('Thursday: done'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Friday: today, not done yet'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Saturday: upcoming'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('starts gently with no streak at all', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpSelectScreen(tester, clock: fixedNow);
    await tester.pumpAndSettle();

    expect(find.text('A pot blooms for every quiet day.'), findsOneWidget);
    expect(find.textContaining('longest'), findsNothing);
    expect(bloomedPots(), findsNothing);
  });

  testWidgets('shows the done state after finishing today', (tester) async {
    SharedPreferences.setMockInitialValues({'daily.days': '["2026-11-06"]'});
    await pumpSelectScreen(tester, clock: fixedNow);
    await tester.pumpAndSettle();

    expect(find.text('1-day streak · longest: 1'), findsOneWidget);
    // The done marker is the bloomed pot on the card, with no status text
    // under the title (owner ruling, UI-2 + follow-up) — never the old
    // stock Material check.
    expect(doneMarker(), findsOneWidget);
    expect(find.text('In progress'), findsNothing);
    expect(find.text('Not started'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(DailyPuzzleCard),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsNothing,
    );
    // Done for the day: no action button, no rule line to follow. (Scoped:
    // other screen areas may legitimately grow FilledButtons later.)
    expect(
      find.descendant(
        of: find.byType(DailyPuzzleCard),
        matching: find.byType(FilledButton),
      ),
      findsNothing,
    );
    expect(find.text("Finish it and today's pot blooms."), findsNothing);
  });

  testWidgets('the card is one screen-reader stop, not a card plus a button', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    SharedPreferences.setMockInitialValues({});
    await pumpSelectScreen(tester, clock: fixedNow);
    await tester.pumpAndSettle();

    // Everything announces through the card's single merged node...
    final card = tester.getSemantics(find.text("TODAY'S PAINTING"));
    expect(
      card.label,
      stringContainsInOrder([
        "TODAY'S PAINTING",
        daily.title,
        'Not started',
        "Finish it and today's pot blooms.",
      ]),
    );
    // ...and the visual Begin button adds no second, redundant stop.
    expect(find.bySemanticsLabel('Begin'), findsNothing);
    semantics.dispose();
  });

  testWidgets('enlarged text stacks the action instead of overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    SharedPreferences.setMockInitialValues({});
    await pumpSelectScreen(tester, clock: fixedNow);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull); // no RenderFlex overflow
    expect(find.widgetWithText(FilledButton, 'Begin'), findsOneWidget);
  });

  testWidgets('a run that blooms yesterday does not promise today', (
    tester,
  ) async {
    // Direct card pump: the select screen can only produce this state when
    // the daily repeats two days running, which the seeded pick controls.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DailyPuzzleCard(
            image: daily,
            doneToday: false,
            inProgress: true,
            bloomsToday: false,
            onPlay: () {},
          ),
        ),
      ),
    );
    expect(find.text('In progress'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
    expect(find.text("Finish it and today's pot blooms."), findsNothing);
  });

  testWidgets('an abandoned save that cannot bloom shows Not started', (
    tester,
  ) async {
    // A consistent save of today's image begun yesterday — when the image
    // was NOT yesterday's daily, finishing it credits nothing, so the card
    // must not claim the daily is in progress.
    expect(dailyPuzzleFor(DateTime(2026, 11, 5)).id, isNot(daily.id));
    final size = puzzleSizes.first;
    SharedPreferences.setMockInitialValues({
      puzzleSaveKey(
        imageId: daily.id,
        columns: size.columns,
        rows: size.rows,
      ): fullTraySave(size.pieceCount, startedDay: '2026-11-05').toJsonString(),
    });
    await pumpSelectScreen(tester, clock: fixedNow);
    await tester.pumpAndSettle();

    expect(find.text('In progress'), findsNothing);
    expect(find.text('Not started'), findsOneWidget);
  });

  testWidgets('the Begin button opens the size picker too', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpSelectScreen(tester, clock: fixedNow);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Begin'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(daily.title),
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping the card opens the size picker for the daily image', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpSelectScreen(tester, clock: fixedNow);
    await tester.pumpAndSettle();

    await tester.tap(find.text("TODAY'S PAINTING"));
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier('puzzle-start'), findsOneWidget);
    // The sheet repeats the daily image's title above the preview.
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(daily.title),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an invalid save from today does not show daily progress', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      puzzleSaveKey(
        imageId: daily.id,
        columns: 5,
        rows: 5,
      ): const PuzzleSaveState(
        trayPieceIndexes: [],
        lockedPieceIndexes: [],
        loosePiecePositions: {},
        startedDay: '2026-11-06',
      ).toJsonString(),
    });
    await pumpSelectScreen(tester, clock: fixedNow);
    await tester.pumpAndSettle();
    expect(find.text('In progress'), findsNothing);
    expect(find.text('Not started'), findsOneWidget);
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
    expect(doneMarker(), findsOneWidget);
    expect(bloomedPots(), findsNWidgets(2));

    now = monday;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: card, matching: find.text(mondayImage.title)),
      findsOneWidget,
    );
    expect(find.text('In progress'), findsOneWidget);
    expect(doneMarker(), findsNothing);
    // An in-progress daily offers to pick the run back up.
    expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
    expect(find.text('2-day streak · longest: 2'), findsOneWidget);
    expect(bloomedPots(), findsNothing);

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
    // Streak broken, but the history stays as one gentle line.
    expect(
      find.text('longest: 2 · pots regrow, no pressure'),
      findsOneWidget,
    );

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
    expect(doneMarker(), findsOneWidget);

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
    expect(doneMarker(), findsNothing);
    expect(find.text('Not started'), findsOneWidget);
    expect(
      find.text('longest: 1 · pots regrow, no pressure'),
      findsOneWidget,
    );
  });
}
