import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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

      // An Alpine daily under the current 80-image catalog.
      DateTime fixedNow() => DateTime(2027, 2, 21, 14);
      final daily = dailyPuzzleFor(fixedNow());
      expect(daily.id, 'alpine-lakes-panorama');
      final savedSize = puzzleSizes[easyInProgress ? 0 : 1];
      SharedPreferences.setMockInitialValues({
        puzzleSaveKey(
          imageId: daily.id,
          columns: savedSize.columns,
          rows: savedSize.rows,
        // Begun today, so the daily card counts it as in progress.
        ): fullTraySave(
          savedSize.pieceCount,
          startedDay: '2027-02-21',
        ).toJsonString(),
      });
      await pumpSelectScreen(tester, clock: fixedNow);
      await tester.pumpAndSettle();

      // The daily card repeats both the catalog title and status text,
      // but must never satisfy the size picker's progress selector.
      expect(find.text('In progress'), findsOneWidget);
      final easyStatus = find.bySemanticsIdentifier(
        'puzzle-in-progress-alpine-lakes-panorama-5x5',
      );
      expect(easyStatus, findsNothing);

      // Filter to Landscapes through its chip — the same identifier the
      // Maestro flow uses (the chips inherited it from the old cards).
      final landscapesChip = find.bySemanticsIdentifier('category-landscapes');
      await scrollSelectScreenTo(tester, landscapesChip, delta: 150);
      await tester.tap(landscapesChip);
      await tester.pumpAndSettle();

      final catalogTitle = catalogPuzzleCard('alpine-lakes-panorama');
      await scrollSelectScreenTo(tester, catalogTitle, delta: 150);
      expect(catalogTitle, findsOneWidget);
      expect(tester.getSemantics(catalogTitle).label, 'Alpine Lake Morning');
      await tester.tap(catalogTitle);
      await tester.pumpAndSettle();

      final easyOption = find.bySemanticsIdentifier(
        'puzzle-size-alpine-lakes-panorama-5x5',
      );
      expect(easyOption.hitTestable(), findsOneWidget);
      expect(tester.getSemantics(easyOption).label, '25 pieces');
      expect(easyStatus, easyInProgress ? findsOneWidget : findsNothing);
      if (easyInProgress) {
        expect(tester.getSemantics(easyStatus).label, 'In progress');
      }

      // Screen-reader activation: the labeled chip node must own the tap
      // action, so a semantics tap (TalkBack/VoiceOver double-tap) changes
      // the selection — the InkWell's separate node is not what's focused.
      final otherOption = find.bySemanticsIdentifier(
        'puzzle-size-alpine-lakes-panorama-'
        '${easyInProgress ? '10x10' : '5x5'}',
      );
      final otherNode = tester.getSemantics(otherOption);
      expect(
        otherNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.tap,
          viewId: tester.view.viewId,
          nodeId: otherNode.id,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Start · ${easyInProgress ? 100 : 25} pieces'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
