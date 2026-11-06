import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/studio_mascots.dart';

/// Keeps the mascot table in lockstep with the catalog, and smoke-paints
/// every motif so a bad path or arc fails here instead of on a screen.
void main() {
  test('every catalog category has an explicit mascot entry', () {
    for (final category in puzzleCategories) {
      expect(
        categoryMascots.containsKey(category.id),
        isTrue,
        reason:
            'Category "${category.id}" would silently fall back to the '
            'palette mascot — add it to categoryMascots.',
      );
    }
  });

  test('the mascot table has no entries for removed categories', () {
    final knownIds = puzzleCategories.map((c) => c.id).toSet();
    for (final id in categoryMascots.keys) {
      expect(knownIds, contains(id));
    }
  });

  testWidgets('every mascot paints', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            for (final mascot in StudioMascot.values)
              MascotArt(mascot, height: 32),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(MascotArt), findsNWidgets(StudioMascot.values.length));
  });
}
