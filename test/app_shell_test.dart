import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/game_screen.dart';
import 'package:jigsaw_puzzle/main.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/my_puzzles_screen.dart';
import 'package:jigsaw_puzzle/puzzle_select_screen.dart';
import 'package:jigsaw_puzzle/settings_screen.dart';
import 'package:jigsaw_puzzle/story_screen.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// Pins the app shell's wiring. Every other test builds its own MaterialApp
/// (to inject a clock), so without these a broken theme, home tab, or nav
/// bar in main.dart would keep the whole suite green.
void main() {
  Finder navDestination(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  Future<void> bootApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const JigsawPuzzleApp());
    await tester.pumpAndSettle();
  }

  testWidgets('boots into the Gallery tab under the studio theme', (
    tester,
  ) async {
    await bootApp(tester);

    expect(find.byType(PuzzleSelectScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.colorScheme.primary, studioTheme().colorScheme.primary);
  });

  testWidgets('the tabs switch between the four screens', (tester) async {
    await bootApp(tester);

    // Constant unique tooltips are the e2e hooks: the labels alone repeat
    // the open tab's AppBar title.
    for (final tooltip in [
      'Gallery tab',
      'Story tab',
      'My Puzzles tab',
      'Settings tab',
    ]) {
      expect(find.byTooltip(tooltip), findsOneWidget);
    }

    // All four tabs stay alive in the shell (IndexedStack), so presence
    // alone proves nothing — hit-testability marks the visible one.
    await tester.tap(navDestination('Story'));
    await tester.pumpAndSettle();
    expect(find.byType(StoryScreen), findsOneWidget);
    expect(find.text('Story').hitTestable(), findsWidgets);
    expect(find.byType(BackButton), findsNothing);

    await tester.tap(navDestination('My Puzzles'));
    await tester.pumpAndSettle();
    expect(find.byType(MyPuzzlesScreen), findsOneWidget);
    expect(find.text('My Puzzles').hitTestable(), findsWidgets);
    // A tab is not a pushed route: no back arrow may appear.
    expect(find.byType(BackButton), findsNothing);

    await tester.tap(navDestination('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(Slider).hitTestable(), findsNWidgets(2));
    expect(find.byType(BackButton), findsNothing);

    await tester.tap(navDestination('Gallery'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a puzzle').hitTestable(), findsOneWidget);
  });

  testWidgets('tab state survives a bottom-nav round trip', (tester) async {
    await bootApp(tester);

    await tester.tap(navDestination('My Puzzles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finished'));
    await tester.pumpAndSettle();

    await tester.tap(navDestination('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(navDestination('My Puzzles'));
    await tester.pumpAndSettle();

    // Still on the Finished tab: the shell keeps tabs alive instead of
    // rebuilding them (and so resetting the selection) on every switch.
    expect(
      find.textContaining("they'll hang here").hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('chips filter in place; only the game covers the nav bar', (
    tester,
  ) async {
    await bootApp(tester);

    // A filter chip is not a route: the grid narrows on the SAME page and
    // the bottom nav stays reachable (layout B replaced the pushed
    // category screens).
    await tester.tap(find.bySemanticsIdentifier('category-landscapes'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar).hitTestable(), findsOneWidget);

    // Launching a puzzle pushes the game on the ROOT navigator — the one
    // route in the flow that must cover the nav bar. No other suite pins
    // this wiring.
    // First LANDSCAPES painting, not puzzleCatalog.first — the grid is
    // filtered by the chip tapped above, and nothing pins the catalog's
    // lead category.
    final tile = catalogPuzzleCard(imagesInCategory('landscapes').first.id);
    await scrollSelectScreenTo(tester, tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('puzzle-start'));
    await tester.runAsync(() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await currentGame(tester).loaded;
    });
    await tester.pump();

    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.byType(NavigationBar).hitTestable(), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar).hitTestable(), findsOneWidget);
  });

  testWidgets('a collection request switches to My Puzzles, Collection tab', (
    tester,
  ) async {
    await bootApp(tester);

    // The journey card's exit reaches the shell through this hook; driving
    // it directly pins the wiring without playing five real games.
    tester
        .widget<PuzzleSelectScreen>(find.byType(PuzzleSelectScreen))
        .onOpenCollection!();
    await tester.pumpAndSettle();

    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    // The inner tab switched to Collection: its journey teaser is the
    // visible, tappable content.
    expect(
      find.text('Finish 5 more puzzles to open the journey.').hitTestable(),
      findsOneWidget,
    );
  });
}
