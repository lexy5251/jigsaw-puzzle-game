// The trail at accessibility text sizes: every state must lay out without
// overflow on a small phone — fixed reserves around scaled text are how
// the mystery card clipped its PLAY button before this pin existed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/story_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';

import 'test_helpers.dart';

void main() {
  Future<void> pumpScaled(WidgetTester tester, Map<String, Object> seed) async {
    SharedPreferences.setMockInitialValues(seed);
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: StoryScreen(clock: previewNow),
        ),
      ),
    );
    // The scroll column lays out ALL trail rows regardless of the
    // viewport, so any overflow anywhere throws and fails the test here.
    await tester.pumpAndSettle();
  }

  testWidgets('a waiting parcel lays out at 2x text on a small phone', (
    tester,
  ) async {
    await pumpScaled(tester, {});
    expect(find.text(storyTapToOpenText), findsOneWidget);
  });

  testWidgets('the torn-open card lays out at 2x text on a small phone', (
    tester,
  ) async {
    await pumpScaled(
      tester,
      Map.fromEntries([
        ...finishedSceneEntries(3).entries,
        storyCelebratedEntry(3, torn: true),
      ]),
    );
    expect(find.text('PLAY'), findsOneWidget);
    expect(find.text(storyNextHintText), findsOneWidget);
  });

  testWidgets('THE END plaque lays out at 2x text on a small phone', (
    tester,
  ) async {
    await pumpScaled(
      tester,
      Map.fromEntries([
        ...finishedSceneEntries(8).entries,
        storyCelebratedEntry(8, finale: true),
      ]),
    );
    expect(find.text(storyEndText), findsOneWidget);
  });
}
