// The trail's painted geometry: segment dots walk the box between the
// stops' positions, the piece slot stays inside its tile, dashing really
// dashes.

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/story_trail_art.dart';

void main() {
  group('segmentDots', () {
    test('dots run from the start stop to the end stop, evenly spaced', () {
      final dots = segmentDots(
        const Size(390, 140),
        fromX: 0.26,
        toX: 0.74,
        spacing: 20,
      );
      expect(dots.length, greaterThan(5));
      expect(dots.first.dx, closeTo(390 * 0.26, 0.1));
      expect(dots.first.dy, closeTo(4, 0.1));
      expect(dots.last.dy, greaterThan(100));
      // Consecutive dots keep the asked arc spacing.
      for (var i = 1; i < dots.length; i++) {
        expect((dots[i] - dots[i - 1]).distance, lessThanOrEqualTo(20.5));
      }
      // Every dot stays inside the band horizontally.
      for (final dot in dots) {
        expect(dot.dx, inInclusiveRange(0, 390));
      }
    });

    test('a centered segment stays centered', () {
      final dots = segmentDots(const Size(390, 90), fromX: 0.5, toX: 0.5);
      for (final dot in dots) {
        expect(dot.dx, closeTo(195, 0.1));
      }
    });
  });

  test('the piece slot path fills its tile without escaping it', () {
    const size = Size(86, 86);
    final bounds = pieceSlotPath(size).getBounds();
    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(bounds.top, greaterThanOrEqualTo(0));
    expect(bounds.right, lessThanOrEqualTo(size.width + 0.1));
    expect(bounds.bottom, lessThanOrEqualTo(size.height + 0.1));
    // It is a real piece, not a sliver: most of the tile is covered.
    expect(bounds.width, greaterThan(size.width * 0.7));
    expect(bounds.height, greaterThan(size.height * 0.7));
  });

  test('dashPath yields disjoint pieces of the source length', () {
    final line = Path()
      ..moveTo(0, 0)
      ..lineTo(100, 0);
    final dashed = dashPath(line, dash: 6, gap: 4);
    final total = dashed
        .computeMetrics()
        .fold<double>(0, (sum, metric) => sum + metric.length);
    // 10 full dash+gap periods of 10px, each keeping its 6px dash.
    expect(total, closeTo(60, 1.5));
    expect(dashed.computeMetrics().length, greaterThan(5));
  });
}
