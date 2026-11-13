import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/game_screen.dart';
import 'package:jigsaw_puzzle/my_puzzles_screen.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_completion.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';
import 'package:jigsaw_puzzle/studio_mascots.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  DateTime fixedNow() => DateTime(2026, 11, 12, 14);

  Future<void> pumpMyPuzzles(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: MyPuzzlesScreen(clock: fixedNow),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder mascots(StudioMascot mascot) => find.byWidgetPredicate(
    (widget) => widget is MascotArt && widget.mascot == mascot,
  );

  testWidgets('lists saved runs and finished photos on their tabs', (
    tester,
  ) async {
    final images = imagesInCategory('landscapes');
    final started = images[0];
    final finished = images[1];
    SharedPreferences.setMockInitialValues({
      puzzleSaveKey(imageId: started.id, columns: 5, rows: 5):
          partiallyPlacedSave(25, placed: 20).toJsonString(),
      puzzleCompletionKey(imageId: finished.id, columns: 5, rows: 5):
          completionOn(DateTime(2026, 11, 9)).toJsonString(),
      puzzleCompletionKey(imageId: finished.id, columns: 10, rows: 10):
          completionOn(DateTime(2026, 11, 10)).toJsonString(),
    });
    await pumpMyPuzzles(tester);

    // In progress is the default tab: a bare photo card — no name, and no
    // progress chip (owner: it sat heavy on the art).
    expect(
      find.bySemanticsIdentifier('my-puzzles-in-progress-${started.id}'),
      findsOneWidget,
    );
    expect(find.text('20/25 pieces'), findsNothing);
    expect(find.text(started.title), findsNothing);
    expect(find.textContaining('Nothing on the easel'), findsNothing);

    await tester.tap(find.text('Finished'));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier('my-puzzles-finished-${finished.id}'),
      findsOneWidget,
    );
    expect(find.text('25 · 100 pieces'), findsOneWidget);
    expect(find.text(finished.title), findsNothing);
    expect(find.textContaining("they'll hang here"), findsNothing);
  });

  testWidgets('empty storage shows an empty state per tab', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpMyPuzzles(tester);

    expect(find.textContaining('Nothing on the easel yet'), findsOneWidget);
    expect(mascots(StudioMascot.sprout), findsOneWidget);

    await tester.tap(find.text('Finished'));
    await tester.pumpAndSettle();

    expect(find.textContaining("they'll hang here"), findsOneWidget);
    expect(mascots(StudioMascot.cactus), findsOneWidget);
  });

  testWidgets('broken, foreign, and catalog-less entries are not listed', (
    tester,
  ) async {
    final images = imagesInCategory('landscapes');
    SharedPreferences.setMockInitialValues({
      puzzleSaveKey(imageId: images[0].id, columns: 5, rows: 5): '{broken',
      // Three of 24 pieces: fails the same consistency check as the badges.
      puzzleSaveKey(imageId: images[1].id, columns: 5, rows: 5): fullTraySave(
        3,
      ).toJsonString(),
      puzzleSaveKey(imageId: 'gone-photo', columns: 5, rows: 5): fullTraySave(
        25,
      ).toJsonString(),
      puzzleCompletionKey(imageId: 'gone-photo', columns: 5, rows: 5):
          completionOn(DateTime(2026, 11, 9)).toJsonString(),
    });
    await pumpMyPuzzles(tester);

    expect(find.textContaining('Nothing on the easel yet'), findsOneWidget);

    await tester.tap(find.text('Finished'));
    await tester.pumpAndSettle();

    expect(find.textContaining("they'll hang here"), findsOneWidget);
  });

  testWidgets('one card per photo; tapping it opens the size sheet', (
    tester,
  ) async {
    final started = imagesInCategory('landscapes').first;
    SharedPreferences.setMockInitialValues({
      // Two runs of the same photo: the card must appear exactly once.
      puzzleSaveKey(imageId: started.id, columns: 5, rows: 5):
          partiallyPlacedSave(
            25,
            placed: 20,
            startedDay: '2026-11-12',
          ).toJsonString(),
      puzzleSaveKey(imageId: started.id, columns: 10, rows: 10):
          partiallyPlacedSave(
            100,
            placed: 57,
            startedDay: '2026-11-10',
          ).toJsonString(),
    });
    await pumpMyPuzzles(tester);

    final card = find.bySemanticsIdentifier(
      'my-puzzles-in-progress-${started.id}',
    );
    expect(card, findsOneWidget);

    await tester.tap(card);
    await tester.pumpAndSettle();

    // The sheet disambiguates the sizes: both runs wear their progress mark,
    // and the first in-progress size is pre-selected as a resume.
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.bySemanticsIdentifier('puzzle-in-progress-${started.id}-5x5'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier('puzzle-in-progress-${started.id}-10x10'),
      findsOneWidget,
    );
    expect(find.text('Resume · 25 pieces'), findsOneWidget);
    expect(find.byType(GameScreen), findsNothing);
  });

  testWidgets('a size finished before but mid-replay reads In progress', (
    tester,
  ) async {
    final photo = imagesInCategory('landscapes').first;
    SharedPreferences.setMockInitialValues({
      // The same size carries a saved replay AND its completion record.
      // Owner's precedence rule: the row says "In progress" (one word,
      // never "Completed") and the button resumes — flipping either
      // branch would re-enable the silent restart the sheet exists to
      // prevent.
      puzzleSaveKey(imageId: photo.id, columns: 5, rows: 5):
          partiallyPlacedSave(
            25,
            placed: 3,
            startedDay: '2026-11-12',
          ).toJsonString(),
      puzzleCompletionKey(imageId: photo.id, columns: 5, rows: 5):
          completionOn(DateTime(2026, 11, 9)).toJsonString(),
    });
    await pumpMyPuzzles(tester);

    await tester.tap(
      find.bySemanticsIdentifier('my-puzzles-in-progress-${photo.id}'),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier('puzzle-in-progress-${photo.id}-5x5'),
      findsOneWidget,
    );
    expect(find.text('Completed'), findsNothing);
    expect(find.text('Resume · 25 pieces'), findsOneWidget);
  });

  testWidgets('tapping a finished card opens the size sheet', (tester) async {
    final finished = imagesInCategory('landscapes').first;
    SharedPreferences.setMockInitialValues({
      puzzleCompletionKey(imageId: finished.id, columns: 5, rows: 5):
          completionOn(DateTime(2026, 11, 9)).toJsonString(),
    });
    await pumpMyPuzzles(tester);

    await tester.tap(find.text('Finished'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier('my-puzzles-finished-${finished.id}'),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    // The next unfinished size is pre-selected, so the finished one is not
    // the default — picking its chip flips the button to an explicit
    // replay (never a silent restart).
    expect(find.text('Start · 100 pieces'), findsOneWidget);
    await tester.tap(
      find.bySemanticsIdentifier('puzzle-size-${finished.id}-5x5'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Play again · 25 pieces'), findsOneWidget);
    expect(find.byType(GameScreen), findsNothing);
  });
}
