import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/daily_puzzle.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  for (final easyInProgress in [false, true]) {
    testWidgets('Maestro selectors distinguish catalog and size status '
        'when the ${easyInProgress ? 'easy' : 'medium'} daily is in progress', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      DateTime fixedNow() => DateTime(2026, 11, 20, 14);
      final daily = dailyPuzzleFor(fixedNow());
      expect(daily.id, 'alpine-lakes-panorama');
      final savedSize = puzzleSizes[easyInProgress ? 0 : 1];
      SharedPreferences.setMockInitialValues({
        puzzleSaveKey(
          imageId: daily.id,
          columns: savedSize.columns,
          rows: savedSize.rows,
        ): PuzzleSaveState(
          trayPieceIndexes: List.generate(savedSize.pieceCount, (i) => i),
          lockedPieceIndexes: const [],
          loosePiecePositions: const {},
          // Begun today, so the daily card counts it as in progress.
          startedDay: '2026-11-20',
        ).toJsonString(),
      });
      await pumpSelectScreen(tester, clock: fixedNow);
      await tester.pumpAndSettle();

      // The daily card repeats both the catalog title and status text,
      // but must never satisfy the size picker's progress selector.
      expect(find.text('In progress'), findsOneWidget);
      final easyStatus = find.bySemanticsIdentifier(
        'puzzle-in-progress-alpine-lakes-panorama-6x4',
      );
      expect(easyStatus, findsNothing);

      // Categories live on their own pages now: open Landscapes first,
      // through the same identifier the Maestro flow uses.
      final landscapesCard = find.bySemanticsIdentifier('category-landscapes');
      await scrollSelectScreenTo(tester, landscapesCard, delta: 150);
      await tester.tap(landscapesCard);
      await tester.pumpAndSettle();

      final catalogTitle = find.bySemanticsIdentifier(
        'catalog-puzzle-alpine-lakes-panorama',
      );
      await scrollSelectScreenTo(tester, catalogTitle, delta: 150);
      expect(catalogTitle, findsOneWidget);
      expect(tester.getSemantics(catalogTitle).label, 'Alpine Lakes Panorama');
      await tester.tap(catalogTitle);
      await tester.pumpAndSettle();

      final easyOption = find.bySemanticsIdentifier(
        'puzzle-size-alpine-lakes-panorama-6x4',
      );
      expect(easyOption.hitTestable(), findsOneWidget);
      expect(tester.getSemantics(easyOption).label, '24 pieces');
      expect(easyStatus, easyInProgress ? findsOneWidget : findsNothing);
      if (easyInProgress) {
        expect(tester.getSemantics(easyStatus).label, 'In progress');
      }
      expect(tester.takeException(), isNull);
    });
  }
}
