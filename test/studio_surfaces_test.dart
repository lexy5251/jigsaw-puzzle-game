// UI-5: every card and photo frame wears the torn-paper edge. These pins
// make a silent revert to plain rounded rects fail, and tie the pieces
// that must share one shape (edge+shadow, clip+ring) to each other.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/studio_surfaces.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';

void main() {
  testWidgets('PaintedCard: edge and shadow share one torn shape', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: const PaintedCard(child: SizedBox(width: 200, height: 100)),
      ),
    );
    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(PaintedCard),
        matching: find.byType(Material),
      ),
    );
    expect(material.shape, isA<TornPaperBorder>());
    // The shadow silhouette must be the same shape as the visible edge.
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: find.byType(PaintedCard),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as ShapeDecoration;
    expect(decoration.shape, same(material.shape));
    expect(decoration.shadows, isNotEmpty);
  });

  testWidgets('FramedArt: clip and mat ring share one torn shape', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FramedArt(seed: 3, child: SizedBox(width: 200, height: 100)),
      ),
    );
    final clipper =
        tester
                .widget<ClipPath>(
                  find.descendant(
                    of: find.byType(FramedArt),
                    matching: find.byType(ClipPath),
                  ),
                )
                .clipper
            as ShapeBorderClipper;
    final shape = clipper.shape as TornPaperBorder;
    expect(shape.seed, 3);
    expect(shape.ringColor, isNotNull);
    // The ring is painted by the foregroundDecoration; pinning it to the
    // clipper's instance is what actually prevents clip/ring drift.
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(FramedArt),
        matching: find.byType(Container),
      ),
    );
    final foreground = container.foregroundDecoration as ShapeDecoration;
    expect(foreground.shape, same(clipper.shape));
  });

  testWidgets('a tiny card paints without throwing', (tester) async {
    // softShadow's -5 spread collapses a 10x10 card's shadow rect to
    // nothing; the border must degrade instead of crashing the paint.
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: const Center(
          child: SizedBox(
            width: 10,
            height: 10,
            child: PaintedCard(child: SizedBox.expand()),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  test('the torn outline is one closed, deterministic contour', () {
    const rect = Rect.fromLTWH(0, 0, 320, 200);
    const border = TornPaperBorder(seed: 2);
    final metrics = border.getOuterPath(rect).computeMetrics().toList();
    expect(metrics, hasLength(1));
    expect(metrics.single.isClosed, isTrue);

    // Same seed → identical path (no shimmer across rebuilds)...
    Offset probe(TornPaperBorder b) => b
        .getOuterPath(rect)
        .computeMetrics()
        .first
        .getTangentForOffset(37)!
        .position;
    expect(probe(border), probe(const TornPaperBorder(seed: 2)));
    // ...different seed → a different tear.
    expect(probe(border), isNot(probe(const TornPaperBorder(seed: 3))));
  });

  test('value equality: rebuild-fresh borders compare equal', () {
    // Material's shape tween, the clipper's shouldReclip, and
    // ShapeDecoration's painter cache all key off ==; identity-only
    // equality would re-tear every card on every rebuild.
    expect(const TornPaperBorder(seed: 2), const TornPaperBorder(seed: 2));
    expect(
      const TornPaperBorder(seed: 2).hashCode,
      const TornPaperBorder(seed: 2).hashCode,
    );
    expect(
      const TornPaperBorder(seed: 2),
      isNot(const TornPaperBorder(seed: 3)),
    );
    expect(
      const TornPaperBorder(seed: 2),
      isNot(const TornPaperBorder(seed: 2, ringColor: Colors.white)),
    );
  });

  test('inner path only insets when a ring exists', () {
    const rect = Rect.fromLTWH(0, 0, 320, 200);
    const ringless = TornPaperBorder(seed: 2);
    expect(
      ringless.getInnerPath(rect).getBounds(),
      ringless.getOuterPath(rect).getBounds(),
    );
    expect(ringless.dimensions, EdgeInsets.zero);
    const ringed = TornPaperBorder(seed: 2, ringColor: Colors.white);
    expect(ringed.dimensions, const EdgeInsets.all(3));
  });

  test('degenerate rects degrade instead of throwing', () {
    const border = TornPaperBorder(seed: 2);
    expect(border.getOuterPath(Rect.zero), isA<Path>());
    // The shadow pre-pass can hand the border an inverted rect.
    expect(
      border.getOuterPath(const Rect.fromLTWH(0, 0, 8, 8).inflate(-5)),
      isA<Path>(),
    );
    expect(
      const TornPaperBorder(
        seed: 2,
        ringColor: Colors.white,
      ).getInnerPath(const Rect.fromLTWH(0, 0, 4, 4)),
      isA<Path>(),
    );
  });
}
