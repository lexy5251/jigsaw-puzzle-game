import 'dart:math';
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

  /// Maps a unit-box point into [shape]'s cell coordinates — the same
  /// normalize-and-center transform buildWhimsyFigurePath applies.
  Offset inCell(WhimsyShape shape, Offset unit) {
    final tight = whimsyUnitBounds(shape);
    // Shorter side is the height.
    final scale =
        whimsyFigureSpans[shape]! * cellHeight / max(tight.width, tight.height);
    return Offset(
      cellWidth / 2 + (unit.dx - tight.center.dx) * scale,
      cellHeight / 2 + (unit.dy - tight.center.dy) * scale,
    );
  }

  group('buildWhimsyFigurePath', () {
    test('every figure stays inside the cell plus its flap neighbors', () {
      // The figure may bite into the four orthogonal neighbors — never into
      // a diagonal one, whose plain knobbed outline knows nothing about it.
      // The plus region is two overlapping slabs; the pad absorbs path-op
      // float noise along shared boundaries.
      const pad = 0.01;
      final plus = Path()
        ..addRect(
          const Rect.fromLTRB(
            -cellWidth,
            -pad,
            2 * cellWidth,
            cellHeight + pad,
          ),
        )
        ..addRect(
          const Rect.fromLTRB(-pad, -cellHeight, cellWidth + pad, 2 * cellHeight),
        );
      for (final shape in WhimsyShape.values) {
        final outside = Path.combine(
          PathOperation.difference,
          figureFor(shape),
          plus,
        );
        expect(
          outside.computeMetrics().isEmpty,
          isTrue,
          reason: '$shape escapes the cell-plus-flap-neighbors region',
        );
      }
    });

    test('figure tips overhang the cell less than a knob tab', () {
      // The renderer gives a whimsy piece the plain knob bleed; a tip
      // protruding past the knob overhang would be clipped off its sprite.
      final allowed = const Rect.fromLTWH(
        0,
        0,
        cellWidth,
        cellHeight,
      ).inflate(knobOverhangFraction * cellHeight);
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

    test('every figure stays inside the plus region on SQUARE cells too', () {
      // The rectangular suite above scales figures by the shorter side, so
      // square cells — the real catalog shape — are the harder corner
      // case, and the one that caught the leaf's diagonal tips reaching
      // the corner squares (owner's find, 2026-11). The builder clips to
      // the plus region; this pins that the clip holds and that no figure
      // is clipped into nothing.
      const square = 100.0;
      const pad = 0.01;
      final plus = Path()
        ..addRect(const Rect.fromLTRB(-square, -pad, 2 * square, square + pad))
        ..addRect(const Rect.fromLTRB(-pad, -square, square + pad, 2 * square))
        ..fillType = PathFillType.nonZero;
      for (final shape in WhimsyShape.values) {
        final figure = buildWhimsyFigurePath(
          shape: shape,
          cellWidth: square,
          cellHeight: square,
        );
        final outside = Path.combine(
          PathOperation.difference,
          figure,
          plus,
        );
        expect(
          outside.computeMetrics().isEmpty,
          isTrue,
          reason: '$shape escapes the plus region on a square cell',
        );
        // The clip must trim tips, not erase figures: the shape's meaty
        // probe point survives, and the figure still spans most of the cell.
        final unitProbe = probes[shape]!;
        final tight = whimsyUnitBounds(shape);
        final scale = whimsyFigureSpans[shape]! /
            max(tight.width, tight.height) *
            square;
        final probe = Offset(
          square / 2 + (unitProbe.dx - tight.center.dx) * scale,
          square / 2 + (unitProbe.dy - tight.center.dy) * scale,
        );
        expect(
          figure.contains(probe),
          isTrue,
          reason: '$shape lost its interior to the clip',
        );
        expect(
          figure.getBounds().longestSide,
          greaterThan(square * 0.8),
          reason: '$shape shrank unexpectedly after the clip',
        );
      }
    });

    test('each axis crosses the seam cleanly or stays clear of it', () {
      // Catalog cells are square — check the sizing rule where it applies.
      // An extreme parked in the dead band just inside the edge would pinch
      // the neighbor's photo into a thread between figure and seam.
      for (final shape in WhimsyShape.values) {
        final tight = whimsyUnitBounds(shape);
        final longest = max(tight.width, tight.height);
        for (final extent in [
          whimsyFigureSpans[shape]! * tight.width / longest,
          whimsyFigureSpans[shape]! * tight.height / longest,
        ]) {
          expect(
            extent <= whimsyAxisInsideMax || extent >= whimsyAxisCrossMin,
            isTrue,
            reason:
                '$shape axis extent $extent sits in the dead band '
                '($whimsyAxisInsideMax, $whimsyAxisCrossMin)',
          );
        }
      }
    });

    test('every figure contains its probe point and has real area', () {
      for (final shape in WhimsyShape.values) {
        final figure = figureFor(shape);
        expect(
          figure.contains(inCell(shape, probes[shape]!)),
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

    test('figure and the four flaps cover the plus region exactly once', () {
      // Sampled over the whimsy cell AND the strips the figure can bite out
      // of the flap neighbors, for every shape: tips crossing the seam move
      // photo between pieces, and any slip would show as a hole or a doubly
      // drawn sliver right on a seam.
      for (final shape in WhimsyShape.values) {
        final figure = figureFor(shape);
        final neighbors = neighborsAround(figure);

        /// How many of the five pieces claim the point [p] (whimsy-cell
        /// coordinates).
        int coverage(Offset p) {
          var count = figure.contains(p) ? 1 : 0;
          for (final entry in neighbors.entries) {
            if (entry.value.contains(p + whimsyOrigin(entry.key))) count++;
          }
          return count;
        }

        var checked = 0;
        const eps = 1.5;
        for (var i = -5; i <= 30; i++) {
          for (var j = -5; j <= 30; j++) {
            final p = Offset(cellWidth * i / 25, cellHeight * j / 25);
            final inX = p.dx >= 0 && p.dx <= cellWidth;
            final inY = p.dy >= 0 && p.dy <= cellHeight;
            // Only the plus region is tiled by these five pieces; diagonal
            // cells belong to pieces this test doesn't build.
            if (!inX && !inY) continue;
            // Skip points near the cell seams, where ownership flips.
            if ((p.dx.abs() < eps || (p.dx - cellWidth).abs() < eps) ||
                (p.dy.abs() < eps || (p.dy - cellHeight).abs() < eps)) {
              continue;
            }
            if (inX && inY) {
              // Skip points near the diagonal seams between flaps.
              final d1 = (p.dy * cellWidth - p.dx * cellHeight).abs();
              final d2 = (p.dy * cellWidth +
                      p.dx * cellHeight -
                      cellWidth * cellHeight)
                  .abs();
              final diagonalScale = Offset(cellWidth, cellHeight).distance;
              if (d1 / diagonalScale < eps || d2 / diagonalScale < eps) {
                continue;
              }
            }
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

    test('the figure bite is the only disturbance to the neighbor', () {
      final figure = figureFor(WhimsyShape.star);
      final outline = buildWhimsyNeighborOutline(
        basePath: flatBase,
        side: WhimsySide.above,
        figurePath: figure,
        cellWidth: cellWidth,
        cellHeight: cellHeight,
      );
      // The star's top tip crosses the shared edge into this neighbor: just
      // above the seam, on the tip's axis, the outline is bitten away.
      expect(
        outline.contains(const Offset(cellWidth / 2, cellHeight - 2)),
        isFalse,
      );
      // Away from the shared edge the neighbor's cell is untouched: its far
      // corners and center stay inside, and nothing extends past its
      // left/right/top edges.
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
