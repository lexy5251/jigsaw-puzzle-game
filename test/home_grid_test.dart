// Layout-B pins: the home shows the WHOLE catalog as one 2-across photo
// grid, narrowed in place by the filter-chip row ("All" + one chip per
// category with images). Grid tiles inherit the retired category page's
// rules: picture-only, straight sticker edges, names in semantics
// (UI-6 + v20 rulings); chips wear the style-C sticker pop when selected.

import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_completion.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';
import 'package:jigsaw_puzzle/puzzle_select_screen.dart';
import 'package:jigsaw_puzzle/studio_surfaces.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// Fixture on the bundled test photo, so these pins stay independent of
/// the real bundled photos. Real category ids: the chips only exist for
/// [puzzleCategories] entries that have images in the catalog.
const _catalog = [
  PuzzleImage(
    id: 'first',
    title: 'First Painting',
    categoryId: 'landscapes',
    fileName: 'test_photo.jpg',
  ),
  PuzzleImage(
    id: 'second',
    title: 'Second Painting',
    categoryId: 'landscapes',
    fileName: 'test_photo.jpg',
  ),
  PuzzleImage(
    id: 'third',
    title: 'Third Painting',
    categoryId: 'cozy',
    fileName: 'test_photo.jpg',
  ),
];

void main() {
  DateTime fixedNow() => DateTime(2026, 11, 6, 14);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpHome(
    WidgetTester tester, {
    List<PuzzleImage> catalog = _catalog,
    Size size = const Size(390, 844),
  }) async {
    await pumpPhoneApp(
      tester,
      PuzzleSelectScreen(clock: fixedNow, catalog: catalog),
      size: size,
    );
    await tester.pumpAndSettle();
  }

  Finder card(String id) => catalogPuzzleCard(id);
  Finder chip(String id) => find.bySemanticsIdentifier('category-$id');

  Tristate chipSelected(WidgetTester tester, Finder finder) =>
      tester.getSemantics(finder).getSemanticsData().flagsCollection.isSelected;

  testWidgets('phones get two photo columns', (tester) async {
    await pumpHome(tester);

    final first = tester.getRect(card('first'));
    final second = tester.getRect(card('second'));
    final third = tester.getRect(card('third'));
    expect(second.top, first.top);
    expect(second.left, greaterThan(first.left));
    // The third card wraps to the next row, under the first.
    expect(third.top, greaterThan(first.top));
    expect(third.left, first.left);
  });

  testWidgets('cards are picture-only; the name lives in semantics', (
    tester,
  ) async {
    await pumpHome(tester);

    for (final id in ['first', 'second', 'third']) {
      expect(
        find.descendant(of: card(id), matching: find.byType(Text)),
        findsNothing,
      );
    }
    expect(tester.getSemantics(card('first')).label, 'First Painting');
  });

  testWidgets('photos wear the sticker border, not the torn frame', (
    tester,
  ) async {
    await pumpHome(tester);

    // Scoped to the tile: the daily card above legitimately frames its art.
    expect(
      find.descendant(of: card('first'), matching: find.byType(FramedArt)),
      findsNothing,
    );
    final container = tester.widget<Container>(
      find.descendant(of: card('first'), matching: find.byType(Container)).first,
    );
    final decoration = container.decoration as BoxDecoration;
    expect(
      decoration.borderRadius,
      const BorderRadius.all(TiltedPhotoCard.cornerRadius),
    );
    expect(decoration.border!.top.color, StudioColors.structureInk);
    final shadow = decoration.boxShadow!.single;
    expect(shadow.color, StudioColors.structureInk);
    expect(shadow.blurRadius, 0);
  });

  testWidgets('cards sit straight — the tilt is retired', (tester) async {
    await pumpHome(tester);

    // Owner's v20 ruling: no rotation on photo grids under the riso chrome.
    for (final id in ['first', 'second']) {
      expect(
        find.descendant(of: card(id), matching: find.byType(Transform)),
        findsNothing,
      );
    }
  });

  testWidgets('tapping a photo still opens the size sheet', (tester) async {
    await pumpHome(tester);

    await tester.tap(card('first'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier('puzzle-start'), findsOneWidget);
  });

  testWidgets('cards announce as buttons', (tester) async {
    // With the visible title gone, semantics are the card's only textual
    // channel — without the button trait a screen reader never says the
    // photo opens anything.
    await pumpHome(tester);

    final data = tester.getSemantics(card('first')).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
  });

  testWidgets('a completed image announces Completed', (tester) async {
    SharedPreferences.setMockInitialValues({
      puzzleCompletionKey(imageId: 'first', columns: 5, rows: 5):
          completionOn(DateTime(2026, 11, 1)).toJsonString(),
    });
    await pumpHome(tester);

    // Its own node, like the sprout badge: completed state must not merge
    // silently into the card's title label.
    expect(find.bySemanticsLabel('Completed'), findsOneWidget);
  });

  testWidgets('a fully locked save with a landed completion shows only the '
      'done sticker, never a 99% pill beside it', (tester) async {
    // An interrupted final snap leaves a 25/25-locked save; once the
    // completion record landed, the painting is done — same rule as the
    // My Puzzles In-progress tab (the review's stacked-markers finding).
    SharedPreferences.setMockInitialValues({
      puzzleSaveKey(imageId: 'first', columns: 5, rows: 5):
          partiallyPlacedSave(25, placed: 25).toJsonString(),
      puzzleCompletionKey(imageId: 'first', columns: 5, rows: 5):
          completionOn(DateTime(2026, 11, 1)).toJsonString(),
    });
    await pumpHome(tester);

    expect(find.bySemanticsLabel('Completed'), findsOneWidget);
    expect(find.bySemanticsLabel('In progress'), findsNothing);
  });

  testWidgets('a fully locked save WITHOUT a completion record keeps its '
      'pill — the save is the retry vehicle', (tester) async {
    SharedPreferences.setMockInitialValues({
      puzzleSaveKey(imageId: 'first', columns: 5, rows: 5):
          partiallyPlacedSave(25, placed: 25).toJsonString(),
    });
    await pumpHome(tester);

    expect(find.bySemanticsLabel('In progress'), findsOneWidget);
    expect(find.bySemanticsLabel('Completed'), findsNothing);
  });

  testWidgets('system back clears the filter before it can pop the page', (
    tester,
  ) async {
    await pumpHome(tester);

    await tester.tap(chip('cozy'));
    await tester.pumpAndSettle();
    expect(card('first'), findsNothing);

    // Android back with a filter active: un-filter, do not exit.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(card('first'), findsOneWidget);
    expect(chipSelected(tester, chip('all')), Tristate.isTrue);
  });

  testWidgets('the chip row accepts mouse drags (web build)', (tester) async {
    // Default dragDevices exclude the mouse and horizontal scrollables get
    // no scrollbar — without the ScrollConfiguration override, chips past
    // the right edge are unreachable for mouse-only users.
    await pumpHome(tester);

    final configuration = tester.widget<ScrollConfiguration>(
      find.ancestor(
        of: chip('all'),
        matching: find.byType(ScrollConfiguration),
      ).first,
    );
    expect(
      configuration.behavior.dragDevices,
      contains(PointerDeviceKind.mouse),
    );
  });

  testWidgets('cards paint an opaque surface under the photo', (tester) async {
    // While the photo decodes (or if it ever fails) the tile must read as a
    // card, not a floating shadow around a transparent hole.
    await pumpHome(tester);

    expect(
      find.descendant(
        of: card('first'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              (widget.decoration as BoxDecoration?)?.color ==
                  StudioColors.card,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a photo that fails to decode falls back to its title', (
    tester,
  ) async {
    const broken = [
      PuzzleImage(
        id: 'broken',
        title: 'Broken Painting',
        categoryId: 'landscapes',
        fileName: 'does_not_exist.jpg',
      ),
    ];
    await pumpHome(tester, catalog: broken);

    expect(
      find.descendant(
        of: card('broken'),
        matching: find.text('Broken Painting'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('All is selected by default and shows every category', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(chipSelected(tester, chip('all')), Tristate.isTrue);
    expect(chipSelected(tester, chip('landscapes')), isNot(Tristate.isTrue));
    // Both categories' paintings share the one grid.
    expect(card('first'), findsOneWidget);
    expect(card('third'), findsOneWidget);
  });

  testWidgets('a category chip narrows the grid in place', (tester) async {
    await pumpHome(tester);

    await tester.tap(chip('cozy'));
    await tester.pumpAndSettle();

    expect(card('third'), findsOneWidget);
    expect(card('first'), findsNothing);
    expect(chipSelected(tester, chip('cozy')), Tristate.isTrue);
    expect(chipSelected(tester, chip('all')), isNot(Tristate.isTrue));

    // Back to All: the full catalog returns.
    await tester.tap(chip('all'));
    await tester.pumpAndSettle();
    expect(card('first'), findsOneWidget);
    expect(card('third'), findsOneWidget);
  });

  testWidgets('categories without images get no chip', (tester) async {
    // Only landscapes and cozy have fixture images; the other six
    // categories must not offer an empty filter.
    await pumpHome(tester);

    expect(chip('all'), findsOneWidget);
    expect(chip('landscapes'), findsOneWidget);
    expect(chip('cozy'), findsOneWidget);
    expect(chip('flowers'), findsNothing);
  });

  testWidgets('screen readers can switch the filter on the chip node', (
    tester,
  ) async {
    // The labeled chip node must own the tap action, so a semantics tap
    // (TalkBack/VoiceOver double-tap) changes the selection — the InkWell's
    // separate node is not what's focused.
    await pumpHome(tester);

    final node = tester.getSemantics(chip('cozy'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.tap,
        viewId: tester.view.viewId,
        nodeId: node.id,
      ),
    );
    await tester.pumpAndSettle();

    expect(card('first'), findsNothing);
    expect(card('third'), findsOneWidget);
  });

  testWidgets('huge text keeps the chip row scrollable and tappable', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpHome(tester);

    // No overflow from the chip row at AX3 text.
    expect(tester.takeException(), isNull);

    // At AX3 the giant daily card pushes the chip row below the fold AND
    // the cozy chip past the right edge. The shared helper handles both
    // axes: vertical scrolling until the row is built, then ensureVisible
    // drives the chip row's own horizontal scrollable.
    await scrollSelectScreenTo(tester, chip('cozy'));
    await tester.tap(chip('cozy'));
    await tester.pumpAndSettle();
    expect(card('first'), findsNothing);
    expect(card('third'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
