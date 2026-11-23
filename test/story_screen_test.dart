// The Story trail's stop states, the one-time celebrations, and the reload
// triggers. Scene titles and art must stay hidden until a scene is read —
// locked slots carry a number and an era tag, nothing else.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/game_haptics.dart';
import 'package:jigsaw_puzzle/game_sounds.dart';
import 'package:jigsaw_puzzle/puzzle_completion.dart';
import 'package:jigsaw_puzzle/story_celebration.dart';
import 'package:jigsaw_puzzle/story_screen.dart';
import 'package:jigsaw_puzzle/story_track.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

class _RecordingSounds implements GameSounds {
  int snaps = 0;
  int rips = 0;
  int completes = 0;

  @override
  Future<void> preload() async {}

  @override
  void playDrop() {}

  @override
  void playSnap() => snaps++;

  @override
  void playRip() => rips++;

  @override
  void playComplete() => completes++;

  @override
  Future<void> dispose() async {}
}

class _RecordingHaptics implements GameHaptics {
  int snaps = 0;
  int completes = 0;

  @override
  void snap() => snaps++;

  @override
  void complete() => completes++;
}

void main() {
  Future<(_RecordingSounds, _RecordingHaptics)> pumpStory(
    WidgetTester tester, {
    bool isActive = true,
  }) async {
    final sounds = _RecordingSounds();
    final haptics = _RecordingHaptics();
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: StoryScreen(
          clock: previewNow,
          isActive: isActive,
          sounds: sounds,
          haptics: haptics,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (sounds, haptics);
  }

  /// [pumpStory] without settling: pumps frames only until the unlock's
  /// snap cue confirms the reveal is mid-flight.
  Future<(_RecordingSounds, _RecordingHaptics)> pumpStoryFrames(
    WidgetTester tester,
  ) async {
    final sounds = _RecordingSounds();
    final haptics = _RecordingHaptics();
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: StoryScreen(clock: previewNow, sounds: sounds, haptics: haptics),
      ),
    );
    for (var i = 0; i < 12 && sounds.snaps == 0; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return (sounds, haptics);
  }

  Future<StoryCelebrations> storedCelebrations() async {
    final prefs = await SharedPreferences.getInstance();
    return StoryCelebrations.fromJson(prefs.getString('story.celebrations'));
  }

  testWidgets('a fresh reader sees the parcel waiting and the rest locked', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpStory(tester);

    expect(find.text('A TRUE STORY'), findsOneWidget);
    expect(find.text('How the Jigsaw Was Born'), findsOneWidget);
    expect(find.text(storyProgressText(0, 8)), findsOneWidget);

    // Scene 1 waits as a parcel: the mystery card (and every painting
    // title) stays unseen until the player tears it open.
    expect(
      find.bySemanticsLabel('Scene 1, a wrapped parcel. Tap to open.'),
      findsOneWidget,
    );
    expect(find.text(storyTapToOpenText), findsOneWidget);
    expect(find.text(storyNextHintText), findsNothing);
    for (final stop in jigsawStory.stops) {
      expect(find.textContaining(stop.image.title), findsNothing);
    }
    // Later scenes are empty missing-piece slots wearing a number and an
    // era tag; the first one explains itself.
    expect(find.bySemanticsLabel(RegExp('not found yet')), findsNWidgets(7));
    expect(find.text(storyNotFoundYetText), findsOneWidget);
    for (var number = 1; number <= 8; number++) {
      expect(find.bySemanticsIdentifier('story-stop-$number'), findsOneWidget);
    }
    // The label must be EXACTLY the announcement — without excludeSemantics
    // the tag's bare number would merge in.
    expect(find.bySemanticsLabel('Scene 3, not found yet'), findsOneWidget);
    // Era tags read as a timeline even while locked.
    expect(find.text('1766'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
    // The trail-end ring must not announce a bare THE END mid-story.
    expect(
      find.bySemanticsLabel("The story's end — not reached yet"),
      findsOneWidget,
    );
  });

  testWidgets('screen readers can tear the parcel via the semantic action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final (sounds, _) = await pumpStory(tester);

    // The stops exclude their descendants, so the node itself must carry
    // the tap action — excludeSemantics alone strips the GestureDetector's.
    final parcel = tester.getSemantics(
      find.bySemanticsIdentifier('story-stop-1'),
    );
    expect(parcel.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

    parcel.owner!.performAction(parcel.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(sounds.rips, 1);
    expect(find.text(storyNextHintText), findsOneWidget);
  });

  testWidgets('tearing the parcel reveals the card once, persistently', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final (sounds, haptics) = await pumpStory(tester);

    await tester.tap(find.bySemanticsIdentifier('story-stop-1'));
    await tester.pumpAndSettle();

    // The parcel became the mystery card: scene number, invitation, PLAY.
    expect(find.text('Scene 1'), findsOneWidget);
    expect(find.text(storyNextHintText), findsOneWidget);
    expect(find.text('PLAY'), findsOneWidget);
    expect(find.text(storyTapToOpenText), findsNothing);
    expect(sounds.rips, 1);
    expect(haptics.snaps, 1);
    expect((await storedCelebrations()).opened, 1);

    // A fresh open shows the card directly — the tear never replays.
    final (sounds2, _) = await pumpStory(tester);
    expect(find.text(storyNextHintText), findsOneWidget);
    expect(sounds2.rips, 0);
  });

  testWidgets('the next scene wraps again even within the same session', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpStory(tester);
    await tester.tap(find.bySemanticsIdentifier('story-stop-1'));
    await tester.pumpAndSettle();
    expect(find.text(storyNextHintText), findsOneWidget);

    // Scene 1 is finished from the game's flows; the SAME State instance
    // reloads — the finished tear controller must not leak into stop 2.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      puzzleCompletionKey(
        imageId: jigsawStory.stops.first.image.id,
        columns: 5,
        rows: 5,
      ),
      completionJson(DateTime(2026, 11, 12)),
    );
    await pumpStory(tester, isActive: false);
    await pumpStory(tester);

    // Stop 2 waits as a parcel — not a pre-torn card.
    expect(
      find.bySemanticsLabel('Scene 2, a wrapped parcel. Tap to open.'),
      findsOneWidget,
    );
    expect(find.text(storyTapToOpenText), findsOneWidget);
    expect(find.text('PLAY'), findsNothing);
  });

  testWidgets('the parcel cannot be torn while its arrival is playing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(finishedSceneEntries(1));
    final sounds = _RecordingSounds();
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: StoryScreen(
          clock: previewNow,
          sounds: sounds,
          haptics: _RecordingHaptics(),
        ),
      ),
    );
    // Walk into the arrival without settling: frames until the snap cue
    // confirms the 2.3s reveal is running.
    for (var i = 0; i < 12 && sounds.snaps == 0; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(sounds.snaps, 1);

    await tester.tap(
      find.bySemanticsIdentifier('story-stop-2'),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(sounds.rips, 0);

    // Once the reveal lands, the same tap tears normally.
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('story-stop-2'));
    await tester.pumpAndSettle();
    expect(sounds.rips, 1);
  });

  testWidgets('leaving the tab mid-reveal does not burn the celebration', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(finishedSceneEntries(1));
    final (sounds, _) = await pumpStoryFrames(tester);
    expect(sounds.snaps, 1);

    // Tab switches away mid-animation: the reveal aborts UNPERSISTED.
    await pumpStory(tester, isActive: false);
    expect((await storedCelebrations()).arrivals, 0);

    // The next visit replays it from the top, then records it.
    final (sounds2, _) = await pumpStory(tester);
    expect(sounds2.snaps, 1);
    expect((await storedCelebrations()).arrivals, 2);
  });

  testWidgets('a tap right as the tear lands does not replay it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final (sounds, _) = await pumpStory(tester);

    await tester.tap(find.bySemanticsIdentifier('story-stop-1'));
    // Exactly the animation's length: completion frames, persist pending.
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.tap(
      find.bySemanticsIdentifier('story-stop-1'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(sounds.rips, 1);
    expect(find.text(storyNextHintText), findsOneWidget);
  });

  testWidgets('a double-tap tears once and opens nothing by itself', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final (sounds, _) = await pumpStory(tester);

    await tester.tap(find.bySemanticsIdentifier('story-stop-1'));
    await tester.tap(
      find.bySemanticsIdentifier('story-stop-1'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(sounds.rips, 1);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('tapping the revealed card starts the normal size-sheet flow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(
      Map.fromEntries([storyCelebratedEntry(0, torn: true)]),
    );
    await pumpStory(tester);
    expect(find.text(storyNextHintText), findsOneWidget);

    // Both taps land before the sheet's barrier exists — the launcher's
    // in-flight guard must swallow the second one. Count WIDGETS, not
    // semantics: a stacked sheet hides the one beneath from semantics.
    await tester.tap(find.bySemanticsIdentifier('story-stop-1'));
    await tester.tap(
      find.bySemanticsIdentifier('story-stop-1'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    // The sheet is where the scene's painting and title first appear.
    expect(
      find.bySemanticsIdentifier(
        'puzzle-size-${jigsawStory.stops.first.image.id}-5x5',
      ),
      findsOneWidget,
    );
    expect(find.text('Start · 25 pieces'), findsOneWidget);
  });

  testWidgets('a locked slot opens nothing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpStory(tester);

    await tester.tap(find.bySemanticsIdentifier('story-stop-3'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('read scenes show titles on the trail, lines on tap', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(
      Map.fromEntries([...finishedSceneEntries(2).entries, storyCelebratedEntry(2)]),
    );
    await pumpStory(tester);

    expect(find.text(storyProgressText(2, 8)), findsOneWidget);
    expect(find.text("The Mapmaker's Shop"), findsOneWidget);
    expect(find.text('The First Cut'), findsOneWidget);
    // Scene lines stay tucked away until the stop is tapped.
    expect(find.textContaining('John Spilsbury'), findsNothing);

    await tester.tap(find.bySemanticsIdentifier('story-stop-1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('John Spilsbury'), findsOneWidget);
    expect(find.text("SCENE 1 · THE MAPMAKER'S SHOP"), findsOneWidget);

    // Its replay offer runs the usual size-sheet flow.
    await tester.tap(find.text('Play again'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);

    // Dismiss the sheet: the top corner is always barrier, never sheet.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Tapping the stop again closes the lines.
    await tester.tap(find.bySemanticsIdentifier('story-stop-1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('John Spilsbury'), findsNothing);

    // Scene 3 waits as the parcel; scene 4 is still a locked secret.
    expect(
      find.bySemanticsLabel('Scene 3, a wrapped parcel. Tap to open.'),
      findsOneWidget,
    );
    expect(find.textContaining(jigsawStory.stops[3].image.title), findsNothing);
    expect(find.bySemanticsLabel(RegExp('not found yet')), findsNWidgets(5));
  });

  testWidgets('a new unlock celebrates once: snap cue, then it is stored', (
    tester,
  ) async {
    // Scene 1 was finished elsewhere; this visit has not seen it arrive.
    SharedPreferences.setMockInitialValues(finishedSceneEntries(1));
    final (sounds, _) = await pumpStory(tester);

    // pumpAndSettle carried the arrival through; its snap cue played and
    // the celebration is now on record.
    expect(sounds.snaps, 1);
    expect((await storedCelebrations()).arrivals, 2);

    // The next visit plays nothing new.
    final (sounds2, _) = await pumpStory(tester);
    expect(sounds2.snaps, 0);
    expect((await storedCelebrations()).arrivals, 2);
  });

  testWidgets('reading every scene blooms the plaque, with a one-time chime', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(finishedSceneEntries(8));
    final (sounds, haptics) = await pumpStory(tester);

    // Header flips, plaque carries the closing line, the count retires.
    expect(find.text('THE END'), findsNWidgets(2));
    expect(find.text(storyEndText), findsOneWidget);
    expect(find.text(storyNextHintText), findsNothing);
    expect(find.bySemanticsLabel(RegExp('not found yet')), findsNothing);
    expect(find.text("The Mapmaker's Shop"), findsOneWidget);
    expect(find.bySemanticsIdentifier('story-progress'), findsNothing);
    expect(sounds.completes, 1);
    expect(haptics.completes, 1);
    expect((await storedCelebrations()).finaleShown, isTrue);

    // The finale never replays; the plaque simply stays.
    final (sounds2, _) = await pumpStory(tester);
    expect(find.text(storyEndText), findsOneWidget);
    expect(sounds2.completes, 0);
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
