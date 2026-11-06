import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';
import 'package:jigsaw_puzzle/studio_mascots.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// A started puzzle must be findable without opening its size sheet
/// (2026-11-06 phone feedback): its category card wears the sprout badge.
void main() {
  DateTime fixedNow() => DateTime(2026, 11, 6, 14);

  Finder sproutBadges() => find.byWidgetPredicate(
    (widget) => widget is MascotArt && widget.mascot == StudioMascot.sprout,
  );

  testWidgets('an image with a save shows the sprout; others do not', (
    tester,
  ) async {
    final images = imagesInCategory('landscapes');
    final started = images.first;
    SharedPreferences.setMockInitialValues({
      puzzleSaveKey(imageId: started.id, columns: 6, rows: 4): PuzzleSaveState(
        trayPieceIndexes: List.generate(24, (index) => index),
        lockedPieceIndexes: const [],
        loosePiecePositions: const {},
      ).toJsonString(),
    });
    await pumpSelectScreen(tester, clock: fixedNow);
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier('category-landscapes'));
    await tester.pumpAndSettle();

    expect(sproutBadges(), findsOneWidget);
    expect(find.bySemanticsLabel('In progress'), findsOneWidget);
  });

  testWidgets('no saves, no sprout badges', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpSelectScreen(tester, clock: fixedNow);
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier('category-landscapes'));
    await tester.pumpAndSettle();

    expect(sproutBadges(), findsNothing);
  });

  final invalidSaves = {
    'malformed': '{broken',
    'empty': const PuzzleSaveState(
      trayPieceIndexes: [],
      lockedPieceIndexes: [],
      loosePiecePositions: {},
    ).toJsonString(),
    'wrong size': const PuzzleSaveState(
      trayPieceIndexes: [0, 1, 2],
      lockedPieceIndexes: [],
      loosePiecePositions: {},
    ).toJsonString(),
    'duplicate piece': PuzzleSaveState(
      trayPieceIndexes: List.filled(24, 0),
      lockedPieceIndexes: const [],
      loosePiecePositions: const {},
    ).toJsonString(),
  };
  for (final entry in invalidSaves.entries) {
    testWidgets('${entry.key} save has no category or size progress label', (
      tester,
    ) async {
      final started = imagesInCategory('landscapes').first;
      SharedPreferences.setMockInitialValues({
        puzzleSaveKey(imageId: started.id, columns: 6, rows: 4): entry.value,
      });
      await pumpSelectScreen(tester, clock: fixedNow);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('category-landscapes'));
      await tester.pumpAndSettle();
      expect(sproutBadges(), findsNothing);
      expect(find.bySemanticsLabel('In progress'), findsNothing);
      await tester.tap(
        find
            .descendant(
              of: find.byType(GridView),
              matching: find.byType(InkWell),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('In progress'), findsNothing);
    });
  }
}
