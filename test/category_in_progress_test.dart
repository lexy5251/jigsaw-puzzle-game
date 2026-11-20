import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';
import 'package:jigsaw_puzzle/riso_markers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// A started puzzle must be findable without opening its size sheet
/// (2026-11-06 phone feedback): its category card wears the progress
/// piece-pill (the sprout's riso successor — same signal, plus how far).
void main() {
  DateTime fixedNow() => DateTime(2026, 11, 6, 14);

  Finder progressPills() => find.byType(ProgressPiecePill);

  testWidgets('an image with a save shows the progress pill; others do not', (
    tester,
  ) async {
    final images = imagesInCategory('landscapes');
    final started = images.first;
    SharedPreferences.setMockInitialValues({
      puzzleSaveKey(imageId: started.id, columns: 5, rows: 5): fullTraySave(
        25,
      ).toJsonString(),
    });
    await pumpSelectScreen(tester, clock: fixedNow);
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier('category-landscapes'));
    await tester.pumpAndSettle();

    expect(progressPills(), findsOneWidget);
    expect(find.bySemanticsLabel('In progress'), findsOneWidget);
  });

  testWidgets('one piece short still reads 99%, never a lying 100%', (
    tester,
  ) async {
    final started = imagesInCategory('landscapes').first;
    SharedPreferences.setMockInitialValues({
      puzzleSaveKey(imageId: started.id, columns: 15, rows: 15):
          partiallyPlacedSave(225, placed: 224).toJsonString(),
    });
    await pumpSelectScreen(tester, clock: fixedNow);
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier('category-landscapes'));
    await tester.pumpAndSettle();

    final pill = tester.widget<ProgressPiecePill>(progressPills());
    expect(pill.percent, 99);
  });

  testWidgets('no saves, no progress pills', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpSelectScreen(tester, clock: fixedNow);
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier('category-landscapes'));
    await tester.pumpAndSettle();

    expect(progressPills(), findsNothing);
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
        puzzleSaveKey(imageId: started.id, columns: 5, rows: 5): entry.value,
      });
      await pumpSelectScreen(tester, clock: fixedNow);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('category-landscapes'));
      await tester.pumpAndSettle();
      expect(progressPills(), findsNothing);
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
