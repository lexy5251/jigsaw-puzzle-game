// UI-6 pins: the category page shows 2-across photo cards on phones with no
// visible titles — the picture is the pitch; the name lives in semantics
// (screen readers and the catalog-puzzle e2e identifier). Round-2 ruling:
// bare images wear straight rounded edges (no torn frame) with a slight
// alternating hand-placed tilt.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/category_screen.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_completion.dart';
import 'package:jigsaw_puzzle/studio_surfaces.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// Fixture category on the bundled test photo, so these pins stay green
/// while the real catalog's photos are being regenerated.
const _category = PuzzleCategory(id: 'test', title: 'Test Collection');
const _catalog = [
  PuzzleImage(
    id: 'first',
    title: 'First Painting',
    categoryId: 'test',
    fileName: 'test_photo.jpg',
  ),
  PuzzleImage(
    id: 'second',
    title: 'Second Painting',
    categoryId: 'test',
    fileName: 'test_photo.jpg',
  ),
  PuzzleImage(
    id: 'third',
    title: 'Third Painting',
    categoryId: 'test',
    fileName: 'test_photo.jpg',
  ),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpCategory(WidgetTester tester) async {
    await pumpPhoneApp(
      tester,
      const CategoryScreen(category: _category, catalog: _catalog),
    );
    await tester.pumpAndSettle();
  }

  Finder card(String id) => catalogPuzzleCard(id);

  testWidgets('phones get two photo columns', (tester) async {
    await pumpCategory(tester);

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
    await pumpCategory(tester);

    for (final id in ['first', 'second', 'third']) {
      expect(
        find.descendant(of: card(id), matching: find.byType(Text)),
        findsNothing,
      );
    }
    expect(tester.getSemantics(card('first')).label, 'First Painting');
  });

  testWidgets('photos wear straight rounded edges, not the torn frame', (
    tester,
  ) async {
    await pumpCategory(tester);

    expect(find.byType(FramedArt), findsNothing);
    final clip = tester.widget<ClipRRect>(
      find.descendant(of: card('first'), matching: find.byType(ClipRRect)),
    );
    expect(
      clip.borderRadius,
      const BorderRadius.all(Radius.circular(12)),
    );
  });

  testWidgets('neighboring cards tilt in alternating directions', (
    tester,
  ) async {
    await pumpCategory(tester);

    Matrix4 tiltOf(String id) => tester
        .widget<Transform>(
          find.descendant(of: card(id), matching: find.byType(Transform)).first,
        )
        .transform;

    // Index 1 of a rotation matrix is sin(angle): nonzero and of opposite
    // sign between grid neighbors.
    final first = tiltOf('first').storage[1];
    final second = tiltOf('second').storage[1];
    expect(first, isNot(0));
    expect(second, isNot(0));
    expect(first.sign, -second.sign);
  });

  testWidgets('tapping a photo still opens the size sheet', (tester) async {
    await pumpCategory(tester);

    await tester.tap(card('first'));
    await tester.pumpAndSettle();

    expect(find.text('25 pieces'), findsOneWidget);
  });

  testWidgets('cards announce as buttons', (tester) async {
    // With the visible title gone, semantics are the card's only textual
    // channel — without the button trait a screen reader never says the
    // photo opens anything.
    await pumpCategory(tester);

    final data = tester.getSemantics(card('first')).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
  });

  testWidgets('a completed image announces Completed', (tester) async {
    SharedPreferences.setMockInitialValues({
      puzzleCompletionKey(imageId: 'first', columns: 5, rows: 5):
          completionOn(DateTime(2026, 11, 1)).toJsonString(),
    });
    await pumpCategory(tester);

    // Its own node, like the sprout badge: completed state must not merge
    // silently into the card's title label.
    expect(find.bySemanticsLabel('Completed'), findsOneWidget);
  });

  testWidgets('cards paint an opaque surface under the photo', (tester) async {
    // While the photo decodes (or if it ever fails) the tile must read as a
    // card, not a floating shadow around a transparent hole.
    await pumpCategory(tester);

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
        categoryId: 'test',
        fileName: 'does_not_exist.jpg',
      ),
    ];
    await pumpPhoneApp(
      tester,
      const CategoryScreen(category: _category, catalog: broken),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: card('broken'),
        matching: find.text('Broken Painting'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
