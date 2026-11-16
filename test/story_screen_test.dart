// The Story page's three row states and its reload triggers. Scene titles
// and art must stay hidden until a scene is read — the locked rows carry
// a number and nothing else.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/puzzle_completion.dart';
import 'package:jigsaw_puzzle/story_screen.dart';
import 'package:jigsaw_puzzle/story_track.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  Future<void> pumpStory(WidgetTester tester, {bool isActive = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: StoryScreen(clock: previewNow, isActive: isActive),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a fresh reader sees the title, scene 1 open, the rest locked', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpStory(tester);

    expect(find.text('A TRUE STORY'), findsOneWidget);
    expect(find.text('How the Jigsaw Was Born'), findsOneWidget);
    expect(find.text(storyProgressText(0, 8)), findsOneWidget);

    // Exactly one playable scene; its painting's title stays unseen.
    expect(find.text(storyNextHintText), findsOneWidget);
    expect(find.text('Scene 1'), findsOneWidget);
    for (final stop in jigsawStory.stops) {
      expect(find.textContaining(stop.image.title), findsNothing);
    }
    // Later scenes are wrapped parcels wearing only their number tags —
    // compact enough that all seven sit on screen at once.
    expect(find.bySemanticsLabel(RegExp('still wrapped')), findsNWidgets(7));
    for (var number = 2; number <= 8; number++) {
      expect(
        find.bySemanticsIdentifier('story-stop-$number'),
        findsOneWidget,
      );
    }
    // The tag's bare number is visual only: the parcel's label must be
    // EXACTLY its announcement — without excludeSemantics the number text
    // merges in and screen readers read "Scene 3, still wrapped 3".
    expect(find.bySemanticsLabel('Scene 3, still wrapped'), findsOneWidget);
  });

  testWidgets('a double-tap opens one size sheet, not two stacked', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpStory(tester);

    // Both taps land before the sheet's barrier exists (no pump between) —
    // the launcher's in-flight guard must swallow the second one. Count
    // WIDGETS, not semantics: a stacked sheet hides the one beneath from
    // the semantics tree, so a semantics probe would always see one.
    await tester.tap(find.bySemanticsIdentifier('story-stop-1'));
    await tester.tap(
      find.bySemanticsIdentifier('story-stop-1'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('read scenes show their painting, title and lines', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(finishedSceneEntries(2));
    await pumpStory(tester);

    expect(find.text(storyProgressText(2, 8)), findsOneWidget);
    expect(find.text("Scene 1 · The Mapmaker's Shop"), findsOneWidget);
    expect(find.textContaining('John Spilsbury'), findsOneWidget);
    expect(find.text('Scene 2 · The First Cut'), findsOneWidget);

    // Scene 3 is the open one now; scene 4 is still a wrapped secret.
    expect(find.text('Scene 3'), findsOneWidget);
    expect(find.text(storyNextHintText), findsOneWidget);
    expect(
      find.textContaining(jigsawStory.stops[3].image.title),
      findsNothing,
    );
    expect(find.bySemanticsLabel(RegExp('still wrapped')), findsNWidgets(5));
  });

  testWidgets('tapping the open scene starts the normal size-sheet flow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpStory(tester);

    await tester.tap(find.bySemanticsIdentifier('story-stop-1'));
    await tester.pumpAndSettle();

    // The sheet is where the scene's painting and title first appear.
    expect(
      find.bySemanticsIdentifier(
        'puzzle-size-${jigsawStory.stops.first.image.id}-5x5',
      ),
      findsOneWidget,
    );
    expect(find.text('Start · 25 pieces'), findsOneWidget);
  });

  testWidgets('a wrapped parcel opens nothing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpStory(tester);

    await tester.tap(find.bySemanticsIdentifier('story-stop-3'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier('puzzle-start'), findsNothing);
  });

  testWidgets('reading every scene ends the story', (tester) async {
    SharedPreferences.setMockInitialValues(finishedSceneEntries(8));
    await pumpStory(tester);

    expect(find.text('THE END'), findsOneWidget);
    expect(find.text(storyEndText), findsOneWidget);
    expect(find.text(storyNextHintText), findsNothing);
    expect(find.bySemanticsLabel(RegExp('still wrapped')), findsNothing);
    expect(find.text("Scene 1 · The Mapmaker's Shop"), findsOneWidget);
    // The hunt is over, so the count line retires with it.
    expect(find.bySemanticsIdentifier('story-progress'), findsNothing);
  });

  testWidgets('becoming the visible tab reloads progress', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpStory(tester, isActive: false);
    expect(find.text(storyProgressText(0, 8)), findsOneWidget);

    // A finish lands from another tab's flows while this one is hidden.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      puzzleCompletionKey(
        imageId: jigsawStory.stops.first.image.id,
        columns: 5,
        rows: 5,
      ),
      completionJson(DateTime(2026, 11, 12)),
    );

    await pumpStory(tester, isActive: true);
    expect(find.text(storyProgressText(1, 8)), findsOneWidget);
  });
}
