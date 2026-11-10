import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/studio_mascots.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// Covers the category cards on the selection screen (UI-3 ruling:
/// owner-made cover art from assets/covers/, no corner mascot chip).
void main() {
  // Image.asset with cacheWidth wraps its AssetImage in a ResizeImage.
  bool showsAsset(Widget widget, String assetName) {
    if (widget is! Image) {
      return false;
    }
    var provider = widget.image;
    if (provider is ResizeImage) {
      provider = provider.imageProvider;
    }
    return provider is AssetImage && provider.assetName == assetName;
  }

  testWidgets('category card wears the dedicated cover, no mascot chip', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpSelectScreen(tester, clock: () => DateTime(2026, 11, 10, 14));
    await tester.pumpAndSettle();

    final landscapesCard = find.bySemanticsIdentifier('category-landscapes');
    await scrollSelectScreenTo(tester, landscapesCard, delta: 150);

    expect(
      find.descendant(
        of: landscapesCard,
        matching: find.byWidgetPredicate(
          (widget) => showsAsset(widget, categoryCoverPath('landscapes')),
        ),
      ),
      findsOneWidget,
    );
    // The corner chip is gone for good — no painted mascot on the card.
    expect(
      find.descendant(of: landscapesCard, matching: find.byType(MascotArt)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
