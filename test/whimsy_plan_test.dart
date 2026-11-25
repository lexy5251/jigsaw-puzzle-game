import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/piece_shapes.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_logic.dart';
import 'package:jigsaw_puzzle/whimsy_plan.dart';
import 'package:jigsaw_puzzle/whimsy_shapes.dart';

void main() {
  group('whimsyCountFor', () {
    test('matches the shipped ladder and is zero elsewhere', () {
      expect(whimsyCountFor(5, 5), 1);
      expect(whimsyCountFor(10, 10), 3);
      expect(whimsyCountFor(12, 12), 5);
      expect(whimsyCountFor(15, 15), 8);
      // Test fixtures and anything non-catalog stay whimsy-free.
      expect(whimsyCountFor(6, 4), 0);
      expect(whimsyCountFor(4, 3), 0);
      expect(whimsyCountFor(1, 1), 0);
    });

    test('covers every catalog size with a nonzero count', () {
      for (final size in puzzleSizes) {
        expect(
          whimsyCountFor(size.columns, size.rows),
          greaterThan(0),
          reason: '${size.pieceCount} pieces',
        );
      }
    });
  });

  group('pickWhimsyCells', () {
    test('meets quota, interior only, Manhattan >= 3 apart — many seeds', () {
      for (final size in puzzleSizes) {
        final quota = whimsyCountFor(size.columns, size.rows);
        for (var seed = 1; seed <= 300; seed++) {
          final cells = pickWhimsyCells(
            columns: size.columns,
            rows: size.rows,
            count: quota,
            random: Xorshift32(seed),
          );
          expect(
            cells.length,
            quota,
            reason: '${size.pieceCount} pieces, seed $seed',
          );
          for (final cell in cells) {
            expect(
              isEdgePiece(cell, size.columns, size.rows),
              isFalse,
              reason: 'cell $cell on ${size.pieceCount} pieces',
            );
          }
          for (var i = 0; i < cells.length; i++) {
            for (var j = i + 1; j < cells.length; j++) {
              final dr =
                  (cells[i] ~/ size.columns - cells[j] ~/ size.columns).abs();
              final dc =
                  (cells[i] % size.columns - cells[j] % size.columns).abs();
              expect(
                dr + dc,
                greaterThanOrEqualTo(3),
                reason: 'seed $seed cells ${cells[i]}/${cells[j]}',
              );
            }
          }
        }
      }
    });

    test('is deterministic per seed and varies across seeds', () {
      List<int> pick(int seed) => pickWhimsyCells(
        columns: 15,
        rows: 15,
        count: 8,
        random: Xorshift32(seed),
      );
      expect(pick(42), pick(42));
      expect(pick(42), isNot(pick(43)));
    });
  });

  group('dealWhimsyShapes', () {
    const pool = [
      WhimsyShape.sailboat,
      WhimsyShape.fish,
      WhimsyShape.heart,
      WhimsyShape.star,
    ];

    test('never deals a shape more than twice', () {
      for (var seed = 1; seed <= 100; seed++) {
        final dealt = dealWhimsyShapes(
          pool: pool,
          count: 8,
          random: Xorshift32(seed),
        );
        expect(dealt, hasLength(8));
        for (final shape in pool) {
          expect(
            dealt.where((s) => s == shape).length,
            lessThanOrEqualTo(2),
            reason: 'seed $seed, $shape',
          );
        }
      }
    });

    test('deals distinct shapes first', () {
      for (var seed = 1; seed <= 50; seed++) {
        final dealt = dealWhimsyShapes(
          pool: pool,
          count: 3,
          random: Xorshift32(seed),
        );
        expect(dealt.toSet(), hasLength(3), reason: 'seed $seed');
      }
    });

    test('is deterministic per seed', () {
      List<WhimsyShape> deal(int seed) =>
          dealWhimsyShapes(pool: pool, count: 8, random: Xorshift32(seed));
      expect(deal(9), deal(9));
    });
  });

  group('whimsyPoolFor', () {
    test('every catalog image can feed the largest board', () {
      // 8 whimsies at two-of-a-kind max needs at least 4 distinct shapes.
      for (final image in fullPuzzleCatalog) {
        final pool = whimsyPoolFor(image);
        expect(
          pool.length,
          greaterThanOrEqualTo(4),
          reason: image.id,
        );
        expect(pool.toSet(), hasLength(pool.length), reason: image.id);
        for (final shape in universalWhimsyShapes) {
          expect(pool, contains(shape), reason: image.id);
        }
      }
    });

    test('every browsable category has a themed set', () {
      for (final category in puzzleCategories) {
        expect(
          whimsyCategoryDefaults,
          contains(category.id),
          reason: category.id,
        );
      }
      expect(whimsyCategoryDefaults, contains(bonusCategoryId));
      expect(whimsyCategoryDefaults, contains(storyCategoryId));
    });
  });

  group('whimsyPlanFor', () {
    const pool = [
      WhimsyShape.cat,
      WhimsyShape.teacup,
      WhimsyShape.heart,
      WhimsyShape.star,
    ];

    test('is deterministic from a save-key seed', () {
      WhimsyPlan plan() => whimsyPlanFor(
        columns: 12,
        rows: 12,
        seed: whimsySeedForKey('save.reading-nook.12x12'),
        pool: pool,
      );
      expect(plan().cells, plan().cells);
      expect(plan().cells, hasLength(5));
    });

    test('whimsySeedForKey owns the namespace prefix', () {
      // The figure stream must differ from the knob stream for the same
      // key, and the prefix is pinned here: changing it would relocate
      // every existing board's figures on resume.
      expect(
        whimsySeedForKey('save.test.5x5'),
        shapeSeedForKey('whimsy.save.test.5x5'),
      );
      expect(
        whimsySeedForKey('save.test.5x5'),
        isNot(shapeSeedForKey('save.test.5x5')),
      );
    });

    test('a small pool caps the count instead of over-dealing', () {
      // Two shapes can fill at most four cells at two-of-a-kind max; a
      // 15x15 board with the universal-only pool gets 4 whimsies, not an
      // assert or a 4-of-a-kind deal.
      final plan = whimsyPlanFor(
        columns: 15,
        rows: 15,
        seed: 7,
        pool: universalWhimsyShapes,
      );
      expect(plan.cells, hasLength(4));
      for (final shape in universalWhimsyShapes) {
        expect(plan.cells.values.where((s) => s == shape).length, 2);
      }
    });

    test('a plan with whimsies sharing a neighbor trips the assert', () {
      // Cells 12 and 14 on a 5x5 are Manhattan distance 2 apart: piece 13
      // borders both, which the renderer cannot cut (one flap per piece).
      const bad = WhimsyPlan({12: WhimsyShape.heart, 14: WhimsyShape.star});
      expect(() => bad.neighborOf(13, 5, 5), throwsAssertionError);
    });

    test('non-catalog grids and empty pools yield the empty plan', () {
      expect(
        whimsyPlanFor(columns: 6, rows: 4, seed: 1, pool: pool).isEmpty,
        isTrue,
      );
      expect(
        whimsyPlanFor(columns: 5, rows: 5, seed: 1, pool: const []).isEmpty,
        isTrue,
      );
    });

    test('neighborOf finds each side and nothing else', () {
      // 5x5 board, whimsy at the center (index 12).
      const plan = WhimsyPlan({12: WhimsyShape.heart});
      expect(
        plan.neighborOf(7, 5, 5),
        (whimsyIndex: 12, side: WhimsySide.above),
      );
      expect(
        plan.neighborOf(17, 5, 5),
        (whimsyIndex: 12, side: WhimsySide.below),
      );
      expect(
        plan.neighborOf(11, 5, 5),
        (whimsyIndex: 12, side: WhimsySide.leftOf),
      );
      expect(
        plan.neighborOf(13, 5, 5),
        (whimsyIndex: 12, side: WhimsySide.rightOf),
      );
      // Diagonals and far cells are not neighbors.
      for (final index in [0, 6, 8, 16, 18, 24]) {
        expect(plan.neighborOf(index, 5, 5), isNull, reason: '$index');
      }
    });

    test('neighborOf does not wrap around row ends', () {
      // Whimsy at the right edge of a row interiorly: cell 13 on a 5x5 is
      // (row 2, col 3); cell 14 is its true right neighbor, cell 15 is the
      // next row's left edge and must NOT match.
      const plan = WhimsyPlan({13: WhimsyShape.star});
      expect(
        plan.neighborOf(14, 5, 5),
        (whimsyIndex: 13, side: WhimsySide.rightOf),
      );
      expect(plan.neighborOf(15, 5, 5), isNull);
    });
  });
}
