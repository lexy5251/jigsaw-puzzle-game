import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/piece_shapes.dart';
import 'package:jigsaw_puzzle/whimsy_shapes.dart';

void main() {
  // Non-square cell on purpose: catches width/height mix-ups that a square
  // cell would hide. Real catalog cells are square.
  const cellWidth = 100.0;
  const cellHeight = 80.0;

  // A point clearly inside each figure, in unit-box coordinates. Probes sit
  // in the figure's meaty part, away from any boundary.
  const probes = {
    WhimsyShape.heart: Offset(0.5, 0.35),
    WhimsyShape.star: Offset(0.5, 0.5),
    WhimsyShape.fish: Offset(0.35, 0.5),
    WhimsyShape.sailboat: Offset(0.52, 0.55),
    WhimsyShape.cat: Offset(0.5, 0.7),
    WhimsyShape.teacup: Offset(0.4, 0.45),
    WhimsyShape.butterfly: Offset(0.25, 0.25),
    WhimsyShape.flower: Offset(0.5, 0.5),
    WhimsyShape.leaf: Offset(0.5, 0.4),
    WhimsyShape.bird: Offset(0.38, 0.42),
    WhimsyShape.moon: Offset(0.35, 0.5),
    WhimsyShape.snowflake: Offset(0.5, 0.5),
  };

  Path figureFor(WhimsyShape shape) => buildWhimsyFigurePath(
    shape: shape,
    cellWidth: cellWidth,
    cellHeight: cellHeight,
  );

  /// Maps a unit-box point into the figure's cell coordinates.
  Offset inCell(Offset unit) {
    final side = whimsyFigureFraction * cellHeight; // shorter side is height
    return Offset(
      (cellWidth - side) / 2 + unit.dx * side,
      (cellHeight - side) / 2 + unit.dy * side,
    );
  }

  group('buildWhimsyFigurePath', () {
    test('every figure stays inside its cell with a photo band around', () {
      // getBounds over-reports around curves (control-point bounds), so the
      // asserted band is looser than the geometric (1 - fraction) / 2.
      final band = 0.06 * cellHeight;
      final allowed = const Rect.fromLTWH(
        0,
        0,
        cellWidth,
        cellHeight,
      ).deflate(band);
      for (final shape in WhimsyShape.values) {
        final bounds = figureFor(shape).getBounds();
        expect(
          allowed.contains(bounds.topLeft) &&
              allowed.contains(bounds.bottomRight),
          isTrue,
          reason: '$shape bounds $bounds escape $allowed',
        );
      }
    });

    test('every figure contains its probe point and has real area', () {
      for (final shape in WhimsyShape.values) {
        final figure = figureFor(shape);
        expect(
          figure.contains(inCell(probes[shape]!)),
          isTrue,
          reason: '$shape should contain its probe',
        );
        final bounds = figure.getBounds();
        // A degenerate path (unclosed scribble) would still pass contains()
        // checks in odd ways; demand a believable footprint.
        expect(bounds.width, greaterThan(0.3 * cellHeight), reason: '$shape');
        expect(bounds.height, greaterThan(0.3 * cellHeight), reason: '$shape');
      }
    });

    test('figures are deterministic and survive metrics iteration', () {
      for (final shape in WhimsyShape.values) {
        expect(figureFor(shape).getBounds(), figureFor(shape).getBounds());
        final metrics = figureFor(shape).computeMetrics().toList();
        expect(metrics, isNotEmpty, reason: '$shape');
        final total = metrics.fold(0.0, (sum, m) => sum + m.length);
        expect(total, greaterThan(cellHeight), reason: '$shape');
      }
    });
  });

  group('buildWhimsyNeighborOutline', () {
    const flatShape = PieceShape(
      top: EdgeType.flat,
      right: EdgeType.flat,
      bottom: EdgeType.flat,
      left: EdgeType.flat,
    );
    final flatBase = buildPiecePath(
      shape: flatShape,
      width: cellWidth,
      height: cellHeight,
    );

    /// Whimsy-cell origin in the local coordinates of the neighbor on [side]
    /// — the same offset buildWhimsyNeighborOutline uses internally.
    Offset whimsyOrigin(WhimsySide side) => switch (side) {
      WhimsySide.above => const Offset(0, cellHeight),
      WhimsySide.below => const Offset(0, -cellHeight),
      WhimsySide.leftOf => const Offset(cellWidth, 0),
      WhimsySide.rightOf => const Offset(-cellWidth, 0),
    };

    Map<WhimsySide, Path> neighborsAround(Path figure) => {
      for (final side in WhimsySide.values)
        side: buildWhimsyNeighborOutline(
          basePath: flatBase,
          side: side,
          figurePath: figure,
          cellWidth: cellWidth,
          cellHeight: cellHeight,
        ),
    };

    test('figure and the four flaps cover the whimsy cell exactly once', () {
      // The star is the hardest case: deep concave notches near the center
      // where all four flap triangles meet.
      for (final shape in [WhimsyShape.star, WhimsyShape.heart]) {
        final figure = figureFor(shape);
        final neighbors = neighborsAround(figure);

        /// How many of the five pieces claim the whimsy-cell point [p].
        int coverage(Offset p) {
          var count = figure.contains(p) ? 1 : 0;
          for (final entry in neighbors.entries) {
            if (entry.value.contains(p + whimsyOrigin(entry.key))) count++;
          }
          return count;
        }

        var checked = 0;
        const eps = 1.5;
        for (var i = 1; i < 25; i++) {
          for (var j = 1; j < 25; j++) {
            final p = Offset(cellWidth * i / 25, cellHeight * j / 25);
            // Skip points near the diagonal seams between flaps.
            final d1 = (p.dy * cellWidth - p.dx * cellHeight).abs();
            final d2 = (p.dy * cellWidth + p.dx * cellHeight -
                    cellWidth * cellHeight)
                .abs();
            final diagonalScale = Offset(cellWidth, cellHeight).distance;
            if (d1 / diagonalScale < eps || d2 / diagonalScale < eps) continue;
            // Skip points hugging the figure boundary: antialias-width zones
            // where contains() legitimately wobbles between the two owners.
            final jitter = [
              const Offset(eps, 0),
              const Offset(-eps, 0),
              const Offset(0, eps),
              const Offset(0, -eps),
            ];
            final inside = figure.contains(p);
            if (jitter.any((d) => figure.contains(p + d) != inside)) continue;

            checked++;
            expect(coverage(p), 1, reason: '$shape at $p');
          }
        }
        // The filters must not eat the test: most of the grid gets checked.
        expect(checked, greaterThan(300), reason: '$shape');
      }
    });

    test('a flap reaches at most the whimsy cell center', () {
      final figure = figureFor(WhimsyShape.heart);
      final neighbors = neighborsAround(figure);
      const slack = 1.0;
      for (final entry in neighbors.entries) {
        final bounds = entry.value.getBounds();
        switch (entry.key) {
          case WhimsySide.above:
            expect(bounds.bottom, lessThanOrEqualTo(1.5 * cellHeight + slack));
          case WhimsySide.below:
            expect(bounds.top, greaterThanOrEqualTo(-cellHeight / 2 - slack));
          case WhimsySide.leftOf:
            expect(bounds.right, lessThanOrEqualTo(1.5 * cellWidth + slack));
          case WhimsySide.rightOf:
            expect(bounds.left, greaterThanOrEqualTo(-cellWidth / 2 - slack));
        }
      }
    });

    test('the flap never disturbs the neighbor away from the shared edge', () {
      final figure = figureFor(WhimsyShape.star);
      final outline = buildWhimsyNeighborOutline(
        basePath: flatBase,
        side: WhimsySide.above,
        figurePath: figure,
        cellWidth: cellWidth,
        cellHeight: cellHeight,
      );
      // The neighbor's own cell is untouched: its far corners and center
      // stay inside, and nothing extends past its left/right/top edges.
      expect(outline.contains(const Offset(1, 1)), isTrue);
      expect(outline.contains(const Offset(cellWidth - 1, 1)), isTrue);
      expect(
        outline.contains(const Offset(cellWidth / 2, cellHeight / 2)),
        isTrue,
      );
      final bounds = outline.getBounds();
      expect(bounds.left, greaterThanOrEqualTo(-0.01));
      expect(bounds.right, lessThanOrEqualTo(cellWidth + 0.01));
      expect(bounds.top, greaterThanOrEqualTo(-0.01));
    });
  });
}
