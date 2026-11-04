import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';

/// Keeps the section-F category style table in lockstep with the catalog.
void main() {
  test('every catalog category has an explicit style entry', () {
    for (final category in puzzleCategories) {
      expect(
        studioCategoryStyles.containsKey(category.id),
        isTrue,
        reason:
            'Category "${category.id}" would silently fall back to the '
            'default accent — add it to studioCategoryStyles.',
      );
    }
  });

  test('the style table has no entries for removed categories', () {
    final knownIds = puzzleCategories.map((c) => c.id).toSet();
    for (final id in studioCategoryStyles.keys) {
      expect(knownIds, contains(id));
    }
  });

  test('category accents are distinct', () {
    final accents = studioCategoryStyles.values.map((s) => s.accent).toSet();
    expect(accents.length, studioCategoryStyles.length);
  });
}
