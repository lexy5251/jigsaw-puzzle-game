import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/piece_shapes.dart';

void main() {
  group('PieceShapeGrid', () {
    const columns = 6;
    const rows = 4;
    final grid = PieceShapeGrid.generate(columns: columns, rows: rows, seed: 7);

    test('border sides are flat, interior sides are not', () {
      for (var row = 0; row < rows; row++) {
        for (var column = 0; column < columns; column++) {
          final shape = grid.shapeAt(row, column);
          expect(shape.top == EdgeType.flat, row == 0);
          expect(shape.bottom == EdgeType.flat, row == rows - 1);
          expect(shape.left == EdgeType.flat, column == 0);
          expect(shape.right == EdgeType.flat, column == columns - 1);
        }
      }
    });

    test('neighbors always interlock: one tab meets one blank', () {
      EdgeType opposite(EdgeType type) =>
          type == EdgeType.tab ? EdgeType.blank : EdgeType.tab;

      for (var row = 0; row < rows; row++) {
        for (var column = 0; column < columns - 1; column++) {
          expect(
            grid.shapeAt(row, column).right,
            opposite(grid.shapeAt(row, column + 1).left),
          );
        }
      }
      for (var row = 0; row < rows - 1; row++) {
        for (var column = 0; column < columns; column++) {
          expect(
            grid.shapeAt(row, column).bottom,
            opposite(grid.shapeAt(row + 1, column).top),
          );
        }
      }
    });

    test('same seed cuts the same puzzle, different seed cuts another', () {
      final same = PieceShapeGrid.generate(
        columns: columns,
        rows: rows,
        seed: 7,
      );
      final other = PieceShapeGrid.generate(
        columns: columns,
        rows: rows,
        seed: 8,
      );

      List<EdgeType> allEdges(PieceShapeGrid g) => [
        for (var index = 0; index < columns * rows; index++) ...[
          g.shapeAtIndex(index).top,
          g.shapeAtIndex(index).right,
          g.shapeAtIndex(index).bottom,
          g.shapeAtIndex(index).left,
        ],
      ];

      expect(allEdges(same), allEdges(grid));
      expect(allEdges(other), isNot(allEdges(grid)));
    });

    test('a cut uses both knob directions, not all one way', () {
      final edges = [
        for (var index = 0; index < columns * rows; index++)
          grid.shapeAtIndex(index).right,
      ];
      expect(edges, contains(EdgeType.tab));
      expect(edges, contains(EdgeType.blank));
    });

    test('shapeAtIndex matches shapeAt(row, column)', () {
      expect(grid.shapeAtIndex(7).top, grid.shapeAt(1, 1).top);
      expect(grid.shapeAtIndex(7).left, grid.shapeAt(1, 1).left);
    });
  });

  group('shapeSeedForKey', () {
    test('matches fixed 32-bit results on every platform', () {
      const expected = {
        '': 0x811C9DC5,
        'a': 0xE40C292C,
        'save.forest.6x4': 2606447319,
        'save.alpine-lakes-panorama.6x4': 1464585572,
        'save.city-window-cat-nap.12x10': 3058832785,
      };
      for (final entry in expected.entries) {
        expect(shapeSeedForKey(entry.key), entry.value, reason: entry.key);
      }
    });

    test('is deterministic and fits in 32 bits', () {
      final seed = shapeSeedForKey('save.forest.6x4');
      expect(shapeSeedForKey('save.forest.6x4'), seed);
      expect(seed, inInclusiveRange(0, 0xFFFFFFFF));
    });

    test('different keys give different seeds', () {
      expect(
        shapeSeedForKey('save.forest.6x4'),
        isNot(shapeSeedForKey('save.forest.10x6')),
      );
    });
  });

  group('buildPiecePath', () {
    const width = 100.0;
    const height = 80.0;
    // Knobs scale with the shorter side (80): overhang = 0.275 * 80 = 22.
    final overhang = knobOverhangFraction * height;

    const allFlat = PieceShape(
      top: EdgeType.flat,
      right: EdgeType.flat,
      bottom: EdgeType.flat,
      left: EdgeType.flat,
    );

    test('an all-flat piece is exactly its base rectangle', () {
      final path = buildPiecePath(shape: allFlat, width: width, height: height);
      expect(path.getBounds(), const Rect.fromLTWH(0, 0, width, height));
    });

    test('a tab extends the piece on its side only', () {
      final path = buildPiecePath(
        shape: const PieceShape(
          top: EdgeType.tab,
          right: EdgeType.flat,
          bottom: EdgeType.flat,
          left: EdgeType.flat,
        ),
        width: width,
        height: height,
      );

      // contains() is exact; getBounds() over-reports around arcs because it
      // returns control-point bounds. The knob apex must reach the promised
      // overhang (so renderers can trust knobOverhangFraction) but not much
      // more than that.
      expect(path.contains(Offset(width / 2, -overhang + 1)), isTrue);
      expect(path.contains(Offset(width / 2, -overhang - 1)), isFalse);

      final bounds = path.getBounds();
      expect(bounds.left, 0);
      expect(bounds.right, width);
      expect(bounds.bottom, height);
    });

    test('a blank does not extend the bounds', () {
      final path = buildPiecePath(
        shape: const PieceShape(
          top: EdgeType.blank,
          right: EdgeType.flat,
          bottom: EdgeType.flat,
          left: EdgeType.flat,
        ),
        width: width,
        height: height,
      );
      expect(path.getBounds(), const Rect.fromLTWH(0, 0, width, height));
    });

    test('a tab bulges outward and a blank cuts inward at the edge center', () {
      final tabbed = buildPiecePath(
        shape: const PieceShape(
          top: EdgeType.tab,
          right: EdgeType.flat,
          bottom: EdgeType.flat,
          left: EdgeType.flat,
        ),
        width: width,
        height: height,
      );
      final blanked = buildPiecePath(
        shape: const PieceShape(
          top: EdgeType.blank,
          right: EdgeType.flat,
          bottom: EdgeType.flat,
          left: EdgeType.flat,
        ),
        width: width,
        height: height,
      );

      final outsideKnobCenter = Offset(width / 2, -overhang / 2);
      final insideKnobCenter = Offset(width / 2, overhang / 2);
      final pieceCenter = Offset(width / 2, height / 2);

      expect(tabbed.contains(outsideKnobCenter), isTrue);
      expect(tabbed.contains(insideKnobCenter), isTrue);
      expect(tabbed.contains(pieceCenter), isTrue);

      expect(blanked.contains(outsideKnobCenter), isFalse);
      expect(blanked.contains(insideKnobCenter), isFalse);
      expect(blanked.contains(pieceCenter), isTrue);
    });

    test('knobs work on every side', () {
      final path = buildPiecePath(
        shape: const PieceShape(
          top: EdgeType.tab,
          right: EdgeType.tab,
          bottom: EdgeType.tab,
          left: EdgeType.tab,
        ),
        width: width,
        height: height,
      );

      // Each knob's apex sits just short of the promised overhang, outward
      // from the middle of its own side.
      final apexes = [
        Offset(width / 2, -overhang + 1),
        Offset(width + overhang - 1, height / 2),
        Offset(width / 2, height + overhang - 1),
        Offset(-overhang + 1, height / 2),
      ];
      for (final apex in apexes) {
        expect(path.contains(apex), isTrue, reason: '$apex');
      }
    });
  });
}
