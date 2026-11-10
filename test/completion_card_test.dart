// The completion card (UI-4): mockup content only — painting, FINISHED
// kicker, title, piece count, hero "Next puzzle" with a quiet exit. No
// streak or mascot celebration; the daily bloom lives on the windowsill.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/completion_card.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/studio_mascots.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';

void main() {
  const image = PuzzleImage(
    id: 'card-test',
    title: 'Card test puzzle',
    categoryId: 'test',
    fileName: 'test_photo.jpg',
  );

  Future<void> pumpCard(
    WidgetTester tester, {
    VoidCallback? onNextPuzzle,
    VoidCallback? onBackToGallery,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: Stack(
          children: [
            const Scaffold(),
            CompletionCard(
              image: image,
              pieceCount: 24,
              onBackToGallery: onBackToGallery ?? () {},
              onNextPuzzle: onNextPuzzle,
            ),
          ],
        ),
      ),
    );
    // Let the fade-in tween finish (plus one frame so it lands on exactly
    // 1 and the card's IgnorePointer releases) before tapping.
    await tester.pump(CompletionCard.fadeDuration);
    await tester.pump();
  }

  testWidgets('shows the mockup content and nothing else', (tester) async {
    await pumpCard(tester, onNextPuzzle: () {});

    expect(find.text('FINISHED'), findsOneWidget);
    expect(find.text('Card test puzzle'), findsOneWidget);
    expect(find.text('24 pieces · no timer, no score'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Next puzzle'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Back to gallery'), findsOneWidget);
    // Celebration-free by ruling: no cactus, sprig, or streak line.
    expect(find.byType(MascotArt), findsNothing);
    expect(find.textContaining('streak'), findsNothing);
  });

  testWidgets('promotes the exit when the category is done', (tester) async {
    var leftToGallery = false;
    await pumpCard(
      tester,
      onNextPuzzle: null,
      onBackToGallery: () => leftToGallery = true,
    );

    expect(find.text('Next puzzle'), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Back to gallery'),
      findsOneWidget,
    );
    await tester.tap(find.text('Back to gallery'));
    expect(leftToGallery, isTrue);
  });

  testWidgets('blocks taps and semantics beneath the card', (tester) async {
    final semantics = tester.ensureSemantics();
    var restartTapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: Stack(
          children: [
            Scaffold(
              appBar: AppBar(
                actions: [
                  IconButton(
                    tooltip: 'Restart puzzle',
                    icon: const Icon(Icons.replay),
                    onPressed: () => restartTapped = true,
                  ),
                ],
              ),
            ),
            CompletionCard(
              image: image,
              pieceCount: 24,
              onBackToGallery: () {},
              onNextPuzzle: () {},
            ),
          ],
        ),
      ),
    );
    await tester.pump(CompletionCard.fadeDuration);
    await tester.pump();

    // A tap where the covered control sits must be swallowed by the
    // card's barrier.
    await tester.tap(find.byTooltip('Restart puzzle'), warnIfMissed: false);
    await tester.pump();
    expect(restartTapped, isFalse);
    // And the barrier's BlockSemantics must drop the covered control from
    // the assistive-tech tree entirely.
    expect(find.bySemanticsLabel('Restart puzzle'), findsNothing);
    semantics.dispose();
  });

  testWidgets('landscape keeps both actions on screen', (tester) async {
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpCard(tester, onNextPuzzle: () {});

    // The side-by-side layout exists so the buttons never start below the
    // fold on landscape phones (the stacked card is taller than 360).
    final hero = tester.getRect(
      find.widgetWithText(FilledButton, 'Next puzzle'),
    );
    final exit = tester.getRect(
      find.widgetWithText(TextButton, 'Back to gallery'),
    );
    expect(hero.bottom, lessThanOrEqualTo(360));
    expect(exit.bottom, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
  });
}
