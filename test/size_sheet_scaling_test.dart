// The size sheet under hostile geometry: huge accessibility text and short
// windows. The 2026-11-13 review found the fixed-layout sheet could overflow
// until the size rows ceased to exist — these cases pin the scrolling
// structure (title + preview + rows scroll, launch button stays pinned).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  Future<void> probe(WidgetTester tester, Size size, double scale) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    SharedPreferences.setMockInitialValues({});
    await pumpSelectScreen(tester, clock: () => DateTime(2026, 12, 12, 14));
    final landscapes = find.bySemanticsIdentifier('category-landscapes');
    await scrollSelectScreenTo(tester, landscapes, delta: 150);
    await tester.tap(landscapes);
    await tester.pumpAndSettle();
    final card = catalogPuzzleCard('alpine-lakes-panorama');
    await scrollSelectScreenTo(tester, card, delta: 150);
    await tester.tap(card);
    await tester.pumpAndSettle();

    // No RenderFlex overflow anywhere.
    expect(tester.takeException(), isNull);
    // The launch button is pinned and hittable.
    expect(
      find.bySemanticsIdentifier('puzzle-start').hitTestable(),
      findsOneWidget,
    );
    // Every size row exists (the scroll view is not lazy) and the deepest
    // one is reachable by scrolling.
    final last = find.bySemanticsIdentifier(
      'puzzle-size-alpine-lakes-panorama-15x15',
    );
    expect(last, findsOneWidget);
    await tester.scrollUntilVisible(
      last,
      80,
      scrollable: find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(last.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'iOS AX3 text on a phone keeps every size reachable',
    (tester) => probe(tester, const Size(390, 844), 3),
  );
  testWidgets(
    '2x text in a short landscape window keeps every size reachable',
    (tester) => probe(tester, const Size(800, 400), 2),
  );
  testWidgets(
    '2x text on a small phone keeps every size reachable',
    (tester) => probe(tester, const Size(320, 568), 2),
  );
}
