// The hand-placed bonus board (owner ruling, 2026-11-26): loose pieces
// rest at seeded scatter spots, dragging one close to its home cell snaps
// it in (and persists through the callback), a far drop returns it, the
// 25th placement turns the card into the celebration with the title and a
// Play button, and assistive tech places a piece with a plain tap action.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/bonus_board.dart';
import 'package:jigsaw_puzzle/game_haptics.dart';
import 'package:jigsaw_puzzle/piece_shapes.dart';
import 'package:jigsaw_puzzle/studio_surfaces.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';

import 'test_helpers.dart';

class _RecordingHaptics implements GameHaptics {
  int snaps = 0;
  int completes = 0;

  @override
  void snap() => snaps++;

  @override
  void complete() => completes++;
}

void main() {
  final seed = shapeSeedForKey('bonus-board.${giftImageOne.id}');

  final placements = <Set<int>>[];
  var plays = 0;
  late _RecordingHaptics haptics;

  setUp(() {
    placements.clear();
    plays = 0;
    haptics = _RecordingHaptics();
  });

  Future<void> pumpBoard(
    WidgetTester tester, {
    Set<int> placedCells = const {},
    required List<int> looseCells,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 370,
              child: SingleChildScrollView(
                child: BonusBoardCard(
                  image: giftImageOne,
                  placedCells: placedCells,
                  looseCells: looseCells,
                  onPlacementChanged: placements.add,
                  onPlay: () => plays++,
                  haptics: haptics,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The drag that carries [cell]'s loose piece from its scatter spot back
  /// onto its home cell.
  Offset dragHome(WidgetTester tester, int cell) {
    final boardSize = tester.getSize(
      find.descendant(
        of: find.byType(FramedArt),
        matching: find.byType(LayoutBuilder),
      ),
    );
    final scatter = bonusScatterFraction(seed, cell);
    return Offset(
      -scatter.dx * boardSize.width,
      -scatter.dy * boardSize.height,
    );
  }

  Finder loosePiece(int cell) =>
      find.bySemanticsIdentifier('bonus-loose-piece-$cell');

  testWidgets('dragging a loose piece home snaps it in and persists', (
    tester,
  ) async {
    final loose = looseCellsFor(
      image: giftImageOne,
      placedCells: const {},
      count: 3,
    );
    await pumpBoard(tester, looseCells: loose);

    expect(find.text('0 of 25 pieces'), findsOneWidget);
    expect(find.text(bonusBoardLooseHintText(3)), findsOneWidget);
    expect(find.text(bonusBoardHintText), findsNothing);

    final cell = loose.first;
    await tester.drag(loosePiece(cell), dragHome(tester, cell));
    await tester.pumpAndSettle();

    expect(loosePiece(cell), findsNothing);
    expect(find.text('1 of 25 pieces'), findsOneWidget);
    expect(find.text(bonusBoardLooseHintText(2)), findsOneWidget);
    expect(placements, [
      {cell},
    ]);
    expect(haptics.snaps, 1);
    expect(haptics.completes, 0);
  });

  testWidgets('a far drop returns the piece to its scatter spot', (
    tester,
  ) async {
    final loose = looseCellsFor(
      image: giftImageOne,
      placedCells: const {},
      count: 1,
    );
    await pumpBoard(tester, looseCells: loose);
    final cell = loose.single;
    final restingCenter = tester.getCenter(loosePiece(cell));

    // Most of the way home, but outside the snap radius: the board size is
    // ~338, a cell ~68, so stopping 60px short is a clear miss.
    final home = dragHome(tester, cell);
    final shortfall = home - Offset.fromDirection(home.direction, 60);
    await tester.drag(loosePiece(cell), shortfall);
    await tester.pumpAndSettle();

    expect(loosePiece(cell), findsOneWidget);
    expect(tester.getCenter(loosePiece(cell)), restingCenter);
    expect(find.text('0 of 25 pieces'), findsOneWidget);
    expect(placements, isEmpty);
    expect(haptics.snaps, 0);
  });

  testWidgets('the 25th placement celebrates with the title and Play', (
    tester,
  ) async {
    final loose = looseCellsFor(
      image: giftImageOne,
      placedCells: const {},
      count: 25,
    );
    final lastCell = loose.last;
    await pumpBoard(
      tester,
      placedCells: {...loose}..remove(lastCell),
      looseCells: [lastCell],
    );

    // The surprise holds until the end: no title while a piece waits.
    expect(find.text(giftImageOne.title), findsNothing);

    await tester.drag(loosePiece(lastCell), dragHome(tester, lastCell));
    await tester.pumpAndSettle();

    expect(find.text(giftImageOne.title), findsOneWidget);
    expect(find.text(bonusBoardCompletedCaption), findsOneWidget);
    expect(find.text('24 of 25 pieces'), findsNothing);
    expect(placements.single, hasLength(25));
    // The last piece gets the completion pulse, not the snap tap.
    expect(haptics.completes, 1);
    expect(haptics.snaps, 0);

    await tester.tap(find.widgetWithText(FilledButton, 'Play this painting'));
    expect(plays, 1);
  });

  testWidgets('assistive tech places a piece with a plain tap action', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final loose = looseCellsFor(
      image: giftImageOne,
      placedCells: const {},
      count: 1,
    );
    await pumpBoard(tester, looseCells: loose);
    final cell = loose.single;

    final node = tester.getSemantics(loosePiece(cell));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();

    expect(loosePiece(cell), findsNothing);
    expect(find.text('1 of 25 pieces'), findsOneWidget);
    expect(placements, [
      {cell},
    ]);
    handle.dispose();
  });

  testWidgets('fresh props merge in new loose pieces, never undo snaps', (
    tester,
  ) async {
    final loose = looseCellsFor(
      image: giftImageOne,
      placedCells: const {},
      count: 2,
    );
    await pumpBoard(tester, looseCells: loose);
    final placedByHand = loose.first;
    await tester.drag(
      loosePiece(placedByHand),
      dragHome(tester, placedByHand),
    );
    await tester.pumpAndSettle();

    // A stale parent rebuild: props still carry the snapped cell as loose,
    // plus a newly earned third piece.
    final refreshed = looseCellsFor(
      image: giftImageOne,
      placedCells: const {},
      count: 3,
    );
    await pumpBoard(tester, looseCells: refreshed);
    await tester.pumpAndSettle();

    expect(loosePiece(placedByHand), findsNothing);
    expect(find.text('1 of 25 pieces'), findsOneWidget);
    expect(find.text(bonusBoardLooseHintText(2)), findsOneWidget);
  });
}
